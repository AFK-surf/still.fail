package dev.mbui;

import android.annotation.SuppressLint;
import android.content.ContentValues;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Bitmap;
import android.graphics.Matrix;
import android.media.MediaDataSource;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.provider.MediaStore;
import android.view.TextureView;
import android.view.View;
import android.view.MotionEvent;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import androidx.annotation.OptIn;
import androidx.media3.common.C;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.Player;
import androidx.media3.common.VideoSize;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.BaseDataSource;
import androidx.media3.datasource.DataSpec;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.SeekParameters;
import androidx.media3.exoplayer.source.ProgressiveMediaSource;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InterruptedIOException;
import java.io.OutputStream;
import java.util.concurrent.ConcurrentHashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Native views over the canvas (src/host/host_native.mbt `view_*`, src/ui/native.mbt). They live in `layer`, a
 * FrameLayout over the MBView in the view tree (so a WebView takes the touches on it) but under its surface on the
 * screen: the MBView's surface is on top of the window and translucent, and the app paints a hole (kind 9,
 * transparent) where a view shows, so what it paints after the hole draws over the view and what it paints around it
 * clips it. Each view sits in a clipping frame at its clip rect, itself at its content rect within it.
 *
 * Kind 1, a video: Media3's ExoPlayer on a TextureView, reading the file through the app (ViewSource: ranged reads
 * the app answers through the core, `station.file.part` or `drive.read`), never from a file or a URL of its own.
 * Kind 2, a page of HTML in a WebView, as still.fail's Android app shows an HTML file (FilePreview.kt HtmlPage):
 * scripts on, no file or content access, no DOM storage, no link followed.
 *
 * Called on the GL thread (MoonBit's); views are made and moved on the main thread.
 */
@OptIn(markerClass = UnstableApi.class)
final class NativeViews {
    static FrameLayout layer;
    static final ConcurrentHashMap<Integer, NView> views = new ConcurrentHashMap<>();
    static final AtomicInteger next = new AtomicInteger();

    /** One read the player waits on, answered once by the app. */
    static final class Read {
        final int id;
        final long offset;
        final int length;
        byte[] data;
        double total;
        boolean done;

        Read(int id, long offset, int length) {
            this.id = id;
            this.offset = offset;
            this.length = length;
        }
    }

    static class NView {
        final int id, kind;
        /** What it is made in: the activity whose layer it is in, switched as it moves to another's (moveTo). */
        android.content.MutableContextWrapper context;
        TouchFrame clip;
        View content;
        volatile boolean closed;
        // how it stands, for info (the GL thread reads these)
        volatile int state;
        volatile double duration = -1, position, playing, nw, nh, bytes, framed, buffering, buffered, ended;
        // placed: x y w h cx0 cy0 cx1 cy1, the content's corners' radius, in pixels; shown
        final float[] at = new float[9];
        boolean shown;
        private boolean told;

        NView(int id, int kind) {
            this.id = id;
            this.kind = kind;
        }

        /**
         * Its readiness told to the app, once (android_host.c's mb_host_set_outside: kind 2, state 1 ready, -1
         * failed): on the GL thread, between frames, from any thread here.
         */
        void tell(int st) {
            synchronized (this) {
                if (told || closed) return;
                told = true;
            }
            Host.view.toGL(() -> Native.outside(Native.OUTSIDE_VIEW, id, st));
        }

        /**
         * What it asks of the app (a player's read, a site's request) put where the app finds it (`ask`), on the GL
         * thread between frames, the app told first that until it answers the view waits on it, not on the host
         * (state 0; not once it is ready): so no frame sees the ask before that is told.
         */
        void askApp(Runnable ask) {
            Host.view.toGL(() -> {
                boolean say;
                synchronized (this) {
                    say = !told && !closed;
                }
                if (say) Native.outside(Native.OUTSIDE_VIEW, id, 0);
                ask.run();
            });
        }

        /**
         * A page's readiness once it is loaded: once what it shows is drawn when it shows (WebView's visual state
         * callback), at once when it does not show (nothing of it is on the screen to wait for). The callback comes
         * only for a view that is drawn; one that does not come within a second is not waited on.
         */
        void pageReady(WebView w) {
            if (w == null) return;
            if (!w.isShown() || w.getWidth() == 0 || w.getHeight() == 0) {
                tell(1);
                return;
            }
            w.postVisualStateCallback(id, new WebView.VisualStateCallback() {
                @Override
                public void onComplete(long requestId) {
                    tell(1);
                }
            });
            Host.main.postDelayed(() -> tell(1), 1000);
        }

        void make(Context c) {}

        void moved() {}

        void control(int op, double value) {}

        void destroy() {}

        // ---- a page's (kind 2) and a site's (kind 3) ----

        /** What it says to the app (siteNext, on the GL thread), oldest first. */
        final ConcurrentLinkedQueue<String> said = new ConcurrentLinkedQueue<>();
        /** Its WebView (a page's, a site's). */
        WebView web;
        /** The scripts the app sent (view_tell 1), waiting for the page there (main thread). */
        final java.util.ArrayList<String> scripts = new java.util.ArrayList<>();
        /** Whether the page there is one scripts run in: loaded, or said something since it started (main thread). */
        boolean there;
        /** A page grabbed (PNG), and how that stands (0 none asked, 1 grabbing, 2 here, -1 failed), as a video's. */
        volatile byte[] still = new byte[0];
        volatile int stillState;

        void say(String json) {
            said.add(json);
            Host.requestFrame();
        }

        /** The page's own way to the app (`mbuiHost.post(text)`, in the page and its frames), on the bridge's thread. */
        final class Bridge {
            @JavascriptInterface
            public void post(String text) {
                if (closed || text == null) return;
                try {
                    say(new org.json.JSONObject().put("said", text).toString());
                } catch (org.json.JSONException e) {
                    return;
                }
                // (said by the page there: what was sent to it runs)
                Host.main.post(() -> {
                    there = true;
                    runScripts();
                });
            }
        }

        /** The page bridged to the app, and told who takes a finger on it (main thread, as it is made). */
        @SuppressLint({"SetJavaScriptEnabled", "JavascriptInterface", "AddJavascriptInterface"})
        void bridge(WebView w) {
            w.addJavascriptInterface(new Bridge(), "mbuiHost");
        }

        /** A new page started: scripts wait for it (main thread). */
        void pageStarted() {
            there = false;
        }

        /** The page loaded: what waits runs (main thread). */
        void pageLoaded() {
            there = true;
            runScripts();
        }

        void runScripts() {
            if (!there || web == null || closed) return;
            for (String js : scripts) web.evaluateJavascript(js, null);
            scripts.clear();
        }

        /** A script the app sent: run in the page there, or kept until it is (any thread). */
        void script(String js) {
            Host.main.post(() -> {
                if (closed) return;
                scripts.add(js);
                runScripts();
            });
        }

        /** What its page shows now, at its view's size, as a PNG (main thread): `still` once it is drawn. */
        void grabPage() {
            stillState = 1;
            still = new byte[0];
            WebView w = web;
            if (w == null || w.getWidth() == 0 || w.getHeight() == 0) {
                stillState = -1;
                Native.tell(Native.OUTSIDE_GRAB, id, -1);
                return;
            }
            try {
                Bitmap b = Bitmap.createBitmap(w.getWidth(), w.getHeight(), Bitmap.Config.ARGB_8888);
                w.draw(new android.graphics.Canvas(b));
                new Thread(() -> {
                    ByteArrayOutputStream out = new ByteArrayOutputStream();
                    b.compress(Bitmap.CompressFormat.PNG, 100, out);
                    b.recycle();
                    still = out.toByteArray();
                    stillState = 2;
                    Host.log("view " + id + ": page grabbed (" + still.length + " bytes)");
                    Native.tell(Native.OUTSIDE_GRAB, id, 1);
                }, "mbui-grab").start();
            } catch (RuntimeException e) {
                Host.log("view " + id + ": page not grabbed: " + e);
                stillState = -1;
                Native.tell(Native.OUTSIDE_GRAB, id, -1);
            }
        }
    }

    /**
     * The frame a view sits in (its clip rect), which takes a finger as the app says (view_tell 2, ui's
     * NativeView::touch): its view's ("all"); the canvas's (MBView: "through", none of it to the view); the view's
     * until a second finger comes down ("pinch") or the finger has gone further up or down than across past the slop
     * ("vertical"; a finger that went sideways past it first stays the view's to its end), the canvas's from there: the
     * view told the touch is called off, the canvas given it from where it went down.
     */
    static final class TouchFrame extends FrameLayout {
        String mode = "all";
        float slop;
        float downX, downY;
        boolean taken;
        /** The finger went sideways past the slop first (vertical): the page's to the end of the touch. */
        boolean sideways;

        TouchFrame(Context c) {
            super(c);
        }

        @Override
        public boolean dispatchTouchEvent(MotionEvent e) {
            // (through: none of it is the view's; MBView, under this layer, is given it by the window)
            if (mode.equals("through")) return false;
            return super.dispatchTouchEvent(e);
        }

        @Override
        public boolean onInterceptTouchEvent(MotionEvent e) {
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downX = e.getX();
                    downY = e.getY();
                    taken = false;
                    sideways = false;
                    return false;
                case MotionEvent.ACTION_POINTER_DOWN:
                    if (mode.equals("pinch")) return take(e);
                    return false;
                case MotionEvent.ACTION_MOVE:
                    if (mode.equals("vertical") && !sideways) {
                        float dx = e.getX() - downX, dy = e.getY() - downY;
                        if (Math.abs(dy) > slop && Math.abs(dy) > Math.abs(dx)) return take(e);
                        // sideways first: the page's
                        if (Math.abs(dx) > slop) sideways = true;
                    }
                    return false;
                default:
                    return false;
            }
        }

        /** The touch the canvas's from now on: it is given it from where it went down (then as it is now). */
        private boolean take(MotionEvent e) {
            taken = true;
            MotionEvent down = MotionEvent.obtain(e.getDownTime(), e.getDownTime(), MotionEvent.ACTION_DOWN, downX, downY, e.getMetaState());
            toCanvas(down);
            down.recycle();
            if (e.getActionMasked() == MotionEvent.ACTION_POINTER_DOWN) {
                // the first finger where it is now, then the second's coming down
                MotionEvent at = MotionEvent.obtain(e.getDownTime(), e.getEventTime(), MotionEvent.ACTION_MOVE, e.getX(0), e.getY(0), e.getMetaState());
                toCanvas(at);
                at.recycle();
            }
            toCanvas(e);
            return true;
        }

        @Override
        public boolean onTouchEvent(MotionEvent e) {
            if (!taken) return false;
            toCanvas(e);
            int a = e.getActionMasked();
            if (a == MotionEvent.ACTION_UP || a == MotionEvent.ACTION_CANCEL) taken = false;
            return true;
        }

        private void toCanvas(MotionEvent e) {
            MBView v = Host.view;
            if (v == null) return;
            MotionEvent m = MotionEvent.obtain(e);
            m.offsetLocation(getLeft() - v.getLeft(), getTop() - v.getTop());
            v.dispatchTouchEvent(m);
            m.recycle();
        }
    }

    // ---- the GL thread ----

    /** Whether the WebView's cookies are being cleared (a run's start: clearCookies), and the sites waiting for it (main thread). */
    static boolean cookiesClearing;
    static final java.util.ArrayList<Runnable> afterCookies = new java.util.ArrayList<>();

    /**
     * A run's start (scripted, driven, taped: MainActivity): the WebView's cookies cleared (they live in the app's data,
     * which a force-stop keeps), so that a run's sites begin with none whatever the last run left; no site opens before
     * it is done (main thread).
     */
    static void clearCookies() {
        cookiesClearing = true;
        CookieManager jar = CookieManager.getInstance();
        jar.removeAllCookies(removed -> {
            jar.flush();
            Host.log("views: cookies cleared for the run");
            cookiesClearing = false;
            for (Runnable r : afterCookies) r.run();
            afterCookies.clear();
        });
    }

    static int open(int kind, String arg) {
        if (kind < 1 || kind > 3) return 0;
        int id = next.incrementAndGet();
        NView v = kind == 1 ? new Video(id, arg) : kind == 2 ? new Page(id, arg) : new Site(id, arg);
        views.put(id, v);
        Host.log("view " + id + ": open " + (kind == 1 ? "video " + arg : kind == 2 ? "page of " + arg.length() + " characters" : "site at " + arg));
        Host.main.post(() -> {
            if (kind == 3 && cookiesClearing) {
                afterCookies.add(() -> make(v, kind));
                return;
            }
            make(v, kind);
        });
        return id;
    }

    /** A view made and put in the layer (main thread). */
    private static void make(NView v, int kind) {
        if (v.closed) return;
        if (layer == null) {
            v.tell(-1);
            return;
        }
        v.context = new android.content.MutableContextWrapper(layer.getContext());
        v.clip = new TouchFrame(v.context);
        v.clip.setClipChildren(true);
        v.clip.setBackgroundColor(kind == 1 ? Color.BLACK : kind == 2 ? Color.WHITE : Color.TRANSPARENT);
        v.clip.setVisibility(View.GONE);
        v.make(v.context);
        layer.addView(v.clip, new FrameLayout.LayoutParams(0, 0));
    }

    static void place(int id, float x, float y, float w, float h, float cx0, float cy0, float cx1, float cy1,
                      float radius, boolean shown) {
        NView v = views.get(id);
        if (v == null) return;
        float d = Host.view.density;
        float[] to = {x * d, y * d, w * d, h * d, cx0 * d, cy0 * d, cx1 * d, cy1 * d, radius * d};
        Host.main.post(() -> {
            if (v.closed || v.clip == null) return;
            boolean same = v.shown == shown;
            for (int i = 0; i < 9 && same; i++) same = Math.abs(v.at[i] - to[i]) < 0.5f;
            if (same) return;
            System.arraycopy(to, 0, v.at, 0, 9);
            v.shown = shown;
            int l = Math.round(to[4]), t = Math.round(to[5]);
            int cw = Math.max(0, Math.round(to[6]) - l), ch = Math.max(0, Math.round(to[7]) - t);
            FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) v.clip.getLayoutParams();
            if (p.leftMargin != l || p.topMargin != t || p.width != cw || p.height != ch) {
                p.leftMargin = l;
                p.topMargin = t;
                p.width = cw;
                p.height = ch;
                v.clip.setLayoutParams(p);
            }
            v.clip.setVisibility(shown && cw > 0 && ch > 0 ? View.VISIBLE : View.GONE);
            v.moved();
            round(v);
            // where it is now, in device pixels (scripts/host_contract.sh HOST views compares it with VIEWTOLD)
            if (shown) {
                Host.log(String.format(java.util.Locale.ROOT, "VIEWAT %d %.4f %.4f %.4f %.4f %d %d %d %d %.4f", id, to[0],
                        to[1], to[2], to[3], l, t, l + cw, t + ch, to[8]));
            }
        });
    }

    /**
     * The content's corners round (at[8], pixels; 0 square): its clipping frame cut to the content's rect within it,
     * rounded (an outline the render thread clips the frame's drawing to, whatever the view in it is: a page, a site,
     * a video's texture), as the hole the app paints for it is.
     */
    private static void round(NView v) {
        boolean on = v.at[8] > 0f;
        if (on && !v.clip.getClipToOutline()) {
            v.clip.setOutlineProvider(new android.view.ViewOutlineProvider() {
                @Override
                public void getOutline(View view, android.graphics.Outline o) {
                    int l = Math.round(v.at[0] - v.at[4]), t = Math.round(v.at[1] - v.at[5]);
                    o.setRoundRect(l, t, l + Math.round(v.at[2]), t + Math.round(v.at[3]), v.at[8]);
                }
            });
            v.clip.setClipToOutline(true);
        } else if (!on && v.clip.getClipToOutline()) {
            v.clip.setClipToOutline(false);
            v.clip.setOutlineProvider(android.view.ViewOutlineProvider.BACKGROUND);
        }
        if (on) v.clip.invalidateOutline();
    }

    /**
     * The layer of the activity resumed (MainActivity's, OverActivity's: each has its own), the views still open moved
     * into it from the other's, where they were placed; laid out in it as they were, and made in it from then on (a
     * WebView's dialogs and pickers in an activity that lives, not in the one finished). On the main thread.
     */
    static void moveTo(FrameLayout to) {
        layer = to;
        for (NView v : views.values()) {
            if (v.closed || v.clip == null || v.clip.getParent() == to) continue;
            android.view.ViewGroup from = (android.view.ViewGroup) v.clip.getParent();
            FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) v.clip.getLayoutParams();
            if (from != null) from.removeView(v.clip);
            v.context.setBaseContext(to.getContext());
            to.addView(v.clip, p);
        }
    }

    static void close(int id) {
        NView v = views.remove(id);
        if (v == null) return;
        v.closed = true;
        Host.log("view " + id + ": closed (" + (long) v.bytes + " bytes given)");
        Host.main.post(() -> {
            v.destroy();
            // out of whichever layer it is in (an activity's other than the one resumed now, not yet moved)
            if (v.clip != null && v.clip.getParent() != null) ((android.view.ViewGroup) v.clip.getParent()).removeView(v.clip);
        });
    }

    static void control(int id, int op, double value) {
        NView v = views.get(id);
        if (v != null) Host.main.post(() -> {
            if (!v.closed) v.control(op, value);
        });
    }

    static int info(int id, double[] out) {
        NView v = views.get(id);
        if (v == null) return -1;
        out[0] = v.duration;
        out[1] = v.position;
        out[2] = v.playing;
        out[3] = v.nw;
        out[4] = v.nh;
        out[5] = v.bytes;
        out[6] = v.framed;
        out[7] = v.buffering;
        out[8] = v.buffered;
        out[9] = v.ended;
        return v.state;
    }

    /**
     * A video's frames' times (`what` 1: ms, comma between; null not read yet) or how its grab stands (2: "0".."2",
     * "-1"); a page's (or a site's) grab, the same.
     */
    static String text(int id, int what) {
        NView v = views.get(id);
        if (v instanceof Video) {
            Video vid = (Video) v;
            return what == 1 ? vid.frames : Integer.toString(vid.stillState);
        }
        if (v != null && v.kind != 1 && what == 2) return Integer.toString(v.stillState);
        return null;
    }

    /** A video's frame grabbed (PNG), or a page's, taken once. */
    static byte[] still(int id) {
        NView v = views.get(id);
        if (v == null) return new byte[0];
        if (v instanceof Video) {
            Video vid = (Video) v;
            byte[] b = vid.still;
            vid.still = new byte[0];
            if (vid.stillState == 2) vid.stillState = 0;
            return b;
        }
        byte[] b = v.still;
        v.still = new byte[0];
        if (v.stillState == 2) v.stillState = 0;
        return b;
    }

    /**
     * What the app tells a view beyond its controls (host_native.mbt view_tell): 1 a script for its page, 2 who takes
     * a finger on it ("MODE SLOP", the slop in points), 3 a site's settings (JSON: head_wait_ms, backlog).
     */
    static void tell(int id, int what, String text) {
        NView v = views.get(id);
        if (v == null) return;
        if (what == 1) {
            v.script(text);
        } else if (what == 2) {
            String[] p = text.split(" ");
            float slop;
            try {
                slop = p.length > 1 ? Float.parseFloat(p[1]) : 0;
            } catch (NumberFormatException e) {
                slop = 0;
            }
            float px = slop * Host.view.density;
            Host.main.post(() -> {
                if (v.clip == null) return;
                v.clip.mode = p[0];
                v.clip.slop = px;
            });
        } else if (what == 3 && v instanceof Site) {
            try {
                org.json.JSONObject o = new org.json.JSONObject(text);
                Site st = (Site) v;
                st.headWaitMs = o.optLong("head_wait_ms", st.headWaitMs);
                st.backlog = o.optLong("backlog", st.backlog);
            } catch (org.json.JSONException e) {
                Host.log("view " + id + ": settings unread: " + e);
            }
        }
    }

    static int readNext(int id, double[] out) {
        NView v = views.get(id);
        if (!(v instanceof Video)) return 0;
        Read r = ((Video) v).asked.poll();
        if (r == null) return 0;
        out[0] = r.offset;
        out[1] = r.length;
        return r.id;
    }

    static void readAnswer(int id, int req, byte[] data, double total) {
        NView v = views.get(id);
        if (!(v instanceof Video)) return;
        Video vid = (Video) v;
        Read r = vid.waiting.remove(req);
        if (r == null) return;
        synchronized (r) {
            r.data = data;
            r.total = total;
            r.done = true;
            r.notifyAll();
        }
        if (data.length > 0) {
            double before = vid.bytes;
            vid.bytes += data.length;
            // the first reads, then one line every 4 MB
            if (vid.reads++ < 4 || Math.floor(before / (4 << 20)) != Math.floor(vid.bytes / (4 << 20))) {
                Host.log("view " + id + ": read @" + r.offset + " " + data.length + " bytes through the app (total "
                        + (long) total + ", " + (long) vid.bytes + " so far)");
            }
        } else if (total == -2) {
            Host.log("view " + id + ": read @" + r.offset + " failed");
        }
    }

    // ---- a site's (kind 3), on the GL thread ----

    static String siteNext(int id) {
        NView v = views.get(id);
        if (v == null || v.kind == 1) return null;
        return v.said.poll();
    }

    static byte[] siteBody(int id, int req) {
        return new byte[0];
    }

    static void siteHead(int id, int req, int status, String headers) {
        NView v = views.get(id);
        if (v instanceof Site) ((Site) v).head(req, status, headers);
    }

    static void siteChunk(int id, int req, byte[] data) {
        NView v = views.get(id);
        if (v instanceof Site) ((Site) v).chunk(req, data);
    }

    static void siteEnd(int id, int req, String error) {
        NView v = views.get(id);
        if (v instanceof Site) ((Site) v).end(req, error);
    }

    static String siteState(int id) {
        NView v = views.get(id);
        return v instanceof Site ? ((Site) v).state() : null;
    }

    static void siteLoad(int id, String path) {
        NView v = views.get(id);
        if (v instanceof Site) Host.main.post(() -> {
            Site s = (Site) v;
            if (!s.closed && s.web != null) s.web.loadUrl("https://" + Site.HOST + path);
        });
    }

    /** A file saved in the phone's Downloads (MediaStore), as the Android app's download() does. */
    static boolean save(String name, byte[] data) {
        Context c = Host.activity;
        if (c == null) return false;
        ContentValues values = new ContentValues();
        values.put(MediaStore.Downloads.DISPLAY_NAME, name);
        Uri uri = c.getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
        if (uri == null) return false;
        try (OutputStream out = c.getContentResolver().openOutputStream(uri)) {
            if (out == null) return false;
            out.write(data);
            Host.log("saved " + name + " (" + data.length + " bytes) to Downloads");
            return true;
        } catch (IOException e) {
            Host.log("save " + name + ": " + e);
            return false;
        }
    }

    // ---- a video ----

    static final class Video extends NView {
        final String type;
        final ConcurrentLinkedQueue<Read> asked = new ConcurrentLinkedQueue<>();
        final ConcurrentHashMap<Integer, Read> waiting = new ConcurrentHashMap<>();
        final AtomicInteger nextRead = new AtomicInteger();
        volatile long total = -1;
        int reads;
        ExoPlayer player;
        TextureView texture;
        final Runnable tick = new Runnable() {
            @Override
            public void run() {
                if (closed || player == null) return;
                position = Math.max(0, player.getCurrentPosition());
                buffered = Math.max(0, player.getBufferedPosition());
                long dur = player.getDuration();
                if (dur != C.TIME_UNSET) duration = dur;
                Host.main.postDelayed(this, playing > 0 ? 33 : 250);
            }
        };

        /** When each frame of its video starts (ms, comma between, in time order): null not read yet, "" none to read. */
        volatile String frames;
        volatile boolean framesAsked;
        /** A frame grabbed (PNG): its bytes once taken, how that stands (0 none asked, 1 grabbing, 2 here, -1 failed). */
        volatile byte[] still = new byte[0];
        volatile int stillState;

        Video(int id, String type) {
            super(id, 1);
            this.type = type;
        }

        /**
         * What the extractor and the retriever have read, in blocks of BLOCK by their place in the file (the last few
         * kept): they ask a few KB at a time, each of which would be a read through the app (and the core's round trip).
         */
        static final int BLOCK = 256 << 10;
        final java.util.LinkedHashMap<Long, byte[]> blocks = new java.util.LinkedHashMap<Long, byte[]>(16, 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(java.util.Map.Entry<Long, byte[]> e) {
                return size() > 16;
            }
        };

        /** Block `at` of the file (BLOCK long, shorter at its end), read once and kept. */
        byte[] block(long at) throws IOException {
            synchronized (blocks) {
                byte[] b = blocks.get(at);
                if (b != null) return b;
            }
            Read r = ask(at * BLOCK, BLOCK);
            // kept whole, or the file's last (a shorter answer before the end is used once, not kept)
            if (r.data.length == BLOCK || (total >= 0 && at * BLOCK + r.data.length >= total)) {
                synchronized (blocks) {
                    blocks.put(at, r.data);
                }
            }
            return r.data;
        }

        /** The file through the app's reads, for the system's extractor and retriever (as the player reads it). */
        final class Media extends MediaDataSource {
            @Override
            public int readAt(long position, byte[] buffer, int offset, int size) throws IOException {
                if (size == 0) return 0;
                if (total >= 0 && position >= total) return -1;
                int n = 0;
                while (n < size) {
                    long p = position + n;
                    if (total >= 0 && p >= total) break;
                    byte[] b = block(p / BLOCK);
                    int in = (int) (p % BLOCK);
                    if (in >= b.length) {
                        // the app gave less than a block before the end: what is asked, as it was before blocks
                        if (total >= 0 && p < total) {
                            Read r = ask(p, Math.min(size - n, 4 << 20));
                            if (r.data.length == 0) break;
                            int k = Math.min(size - n, r.data.length);
                            System.arraycopy(r.data, 0, buffer, offset + n, k);
                            n += k;
                        }
                        break;
                    }
                    int k = Math.min(size - n, b.length - in);
                    System.arraycopy(b, in, buffer, offset + n, k);
                    n += k;
                    // a short block: the file's end (or a short answer: the rest asked next time)
                    if (b.length < BLOCK) break;
                }
                return n == 0 ? -1 : n;
            }

            @Override
            public long getSize() throws IOException {
                if (total < 0) ask(0, 1);
                return total;
            }

            @Override
            public void close() {
            }
        }

        /** Its frames' times read from the file (MediaExtractor: the video track's samples, sorted), off the main thread. */
        void readFrames() {
            if (framesAsked) return;
            framesAsked = true;
            new Thread(() -> {
                MediaExtractor x = new MediaExtractor();
                StringBuilder out = new StringBuilder();
                try {
                    x.setDataSource(new Media());
                    int track = -1;
                    for (int i = 0; i < x.getTrackCount(); i++) {
                        String mime = x.getTrackFormat(i).getString(MediaFormat.KEY_MIME);
                        if (mime != null && mime.startsWith("video/")) { track = i; break; }
                    }
                    if (track >= 0) {
                        x.selectTrack(track);
                        java.util.ArrayList<Long> times = new java.util.ArrayList<>();
                        while (true) {
                            long t = x.getSampleTime();
                            if (t < 0) break;
                            times.add(t);
                            if (!x.advance()) break;
                        }
                        java.util.Collections.sort(times);
                        for (int i = 0; i < times.size(); i++) {
                            if (i > 0) out.append(',');
                            out.append(times.get(i) / 1000.0);
                        }
                    }
                    Host.log("view " + id + ": " + (out.length() == 0 ? 0 : out.toString().split(",").length) + " frames read");
                } catch (Exception e) {
                    Host.log("view " + id + ": frames not read: " + e);
                } finally {
                    x.release();
                }
                frames = out.toString();
                Host.requestFrame();
            }, "mbui-frames").start();
        }

        /** The frame showing at `ms` grabbed whole at its own size (MediaMetadataRetriever, the closest), as a PNG. */
        void grab(double ms) {
            stillState = 1;
            still = new byte[0];
            new Thread(() -> {
                MediaMetadataRetriever r = new MediaMetadataRetriever();
                try {
                    r.setDataSource(new Media());
                    Bitmap b = r.getFrameAtTime((long) (ms * 1000), MediaMetadataRetriever.OPTION_CLOSEST);
                    if (b == null) throw new IOException("no frame at " + ms + " ms");
                    ByteArrayOutputStream out = new ByteArrayOutputStream();
                    b.compress(Bitmap.CompressFormat.PNG, 100, out);
                    b.recycle();
                    still = out.toByteArray();
                    stillState = 2;
                    Host.log("view " + id + ": frame at " + ms + " ms grabbed (" + still.length + " bytes)");
                } catch (Exception e) {
                    Host.log("view " + id + ": frame not grabbed: " + e);
                    stillState = -1;
                } finally {
                    try { r.release(); } catch (Exception ignored) { }
                }
                Native.tell(Native.OUTSIDE_GRAB, id, stillState == 2 ? 1 : -1);
            }, "mbui-grab").start();
        }

        /** Bytes from `offset` (at most `length`), asked of the app and waited for: on the player's loading thread. */
        Read ask(long offset, int length) throws IOException {
            Read r = new Read(nextRead.incrementAndGet(), offset, length);
            waiting.put(r.id, r);
            askApp(() -> asked.add(r));
            long until = System.nanoTime() + TimeUnit.SECONDS.toNanos(120);
            synchronized (r) {
                while (!r.done) {
                    if (closed) throw new InterruptedIOException("view " + id + " closed");
                    long left = until - System.nanoTime();
                    if (left <= 0) {
                        waiting.remove(r.id);
                        throw new IOException("view " + id + ": no answer for the read at " + offset,
                                new TimeoutException());
                    }
                    try {
                        r.wait(Math.min(250, TimeUnit.NANOSECONDS.toMillis(left) + 1));
                    } catch (InterruptedException e) {
                        waiting.remove(r.id);
                        throw new InterruptedIOException();
                    }
                }
            }
            if (r.total == -2) throw new IOException("view " + id + ": the read at " + offset + " failed");
            if (r.total >= 0) total = (long) r.total;
            return r;
        }

        @Override
        void make(Context c) {
            texture = new TextureView(c);
            clip.addView(texture, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT));
            texture.addOnLayoutChangeListener((view, l, t, r, b, ol, ot, or, ob) -> moved());
            player = new ExoPlayer.Builder(c).build();
            player.setSeekParameters(SeekParameters.EXACT);
            player.setVideoTextureView(texture);
            player.addListener(new Player.Listener() {
                @Override
                public void onPlaybackStateChanged(int s) {
                    if (s == Player.STATE_READY && state == 0) {
                        state = 1;
                        long dur = player.getDuration();
                        if (dur != C.TIME_UNSET) duration = dur;
                        Host.log("view " + id + ": ready, " + (long) duration + " ms");
                    }
                    // a player with no picture (a sound) is ready for the app once it can play; one with a picture once
                    // its first frame shows (onRenderedFirstFrame)
                    if (s == Player.STATE_READY && !player.getCurrentTracks().containsType(C.TRACK_TYPE_VIDEO)) tell(1);
                    buffering = s == Player.STATE_BUFFERING ? 1 : 0;
                    ended = s == Player.STATE_ENDED ? 1 : 0;
                    if (s == Player.STATE_ENDED) playing = 0;
                    Host.requestFrame();
                }

                @Override
                public void onIsPlayingChanged(boolean is) {
                    playing = is ? 1 : 0;
                    if (is) {
                        Host.main.removeCallbacks(tick);
                        Host.main.post(tick);
                    }
                    Host.requestFrame();
                }

                @Override
                public void onVideoSizeChanged(VideoSize s) {
                    if (s.width > 0 && s.height > 0) {
                        nw = s.width * s.pixelWidthHeightRatio;
                        nh = s.height;
                        Host.requestFrame();
                    }
                }

                @Override
                public void onRenderedFirstFrame() {
                    if (framed == 0) Host.log("view " + id + ": first frame shown");
                    framed = 1;
                    tell(1);  // ready for the app: its first frame shows
                    Host.requestFrame();
                }

                @Override
                public void onPlayerError(PlaybackException e) {
                    state = -1;
                    playing = 0;
                    Host.log("view " + id + ": cannot play: " + e.getErrorCodeName() + " " + e.getMessage());
                    tell(-1);
                    Host.requestFrame();
                }
            });
            ProgressiveMediaSource source = new ProgressiveMediaSource.Factory(() -> new ViewSource(this))
                    .createMediaSource(MediaItem.fromUri("mbview://" + id + "/file"));
            player.setMediaSource(source);
            player.prepare();
            Host.main.post(tick);
        }

        @Override
        void moved() {
            // the picture where the app puts it, within the clip: the texture fills the clip, its transform makes it
            // the picture's rect (as the Android app's VideoViewer does)
            if (texture == null || texture.getWidth() == 0 || texture.getHeight() == 0) return;
            Matrix m = new Matrix();
            m.setScale(at[2] / texture.getWidth(), at[3] / texture.getHeight());
            m.postTranslate(at[0] - at[4], at[1] - at[5]);
            texture.setTransform(m);
        }

        @Override
        void control(int op, double value) {
            if (player == null) return;
            switch (op) {
                case 1:
                    if (player.getPlaybackState() == Player.STATE_ENDED) player.seekTo(0);
                    player.play();
                    break;
                case 2: player.pause(); break;
                case 3:
                    player.seekTo((long) value);
                    position = value;
                    break;
                case 4: player.setPlaybackParameters(new PlaybackParameters((float) value)); break;
                case 20: readFrames(); break;
                case 21: grab(value); break;
                default: break;
            }
        }

        @Override
        void destroy() {
            Host.main.removeCallbacks(tick);
            for (Read r : waiting.values()) {
                synchronized (r) {
                    r.notifyAll();
                }
            }
            if (player != null) player.release();
            player = null;
        }
    }

    /**
     * What the player reads the file through: ranged reads asked of the app (DriveSource.kt's window: small first,
     * doubling while reads run on from each other up to a core's part of 4 MB, small again after a jump; what is in
     * the window served from it, as the extractor reopens around seeks).
     */
    static final class ViewSource extends BaseDataSource {
        static final int FIRST = 256 * 1024, MAX = 4 << 20;
        final Video v;
        Uri uri;
        long position, remaining;
        byte[] window = new byte[0];
        long windowStart;
        int windowValid, cursor, planned = FIRST;
        boolean opened;

        ViewSource(Video v) {
            super(true);
            this.v = v;
        }

        @Override
        public long open(DataSpec spec) throws IOException {
            uri = spec.uri;
            long start = spec.position;
            position = start;
            if (start < windowStart || start >= windowStart + windowValid) {
                windowStart = start;
                windowValid = 0;
            }
            cursor = (int) (start - windowStart);
            transferInitializing(spec);
            if (v.total < 0 && !fill() && v.total < 0) v.total = start;
            if (start > v.total) throw new IOException("the file is " + v.total + " bytes, opened at " + start);
            remaining = spec.length == C.LENGTH_UNSET ? v.total - start : Math.min(spec.length, v.total - start);
            opened = true;
            transferStarted(spec);
            return remaining;
        }

        @Override
        public int read(byte[] buffer, int offset, int length) throws IOException {
            if (length == 0) return 0;
            if (remaining <= 0) return C.RESULT_END_OF_INPUT;
            if (cursor >= windowValid && !fill()) return C.RESULT_END_OF_INPUT;
            int n = (int) Math.min(Math.min(length, windowValid - cursor), remaining);
            System.arraycopy(window, cursor, buffer, offset, n);
            cursor += n;
            position += n;
            remaining -= n;
            bytesTransferred(n);
            return n;
        }

        /** The window read from `position`; false at the file's end. */
        boolean fill() throws IOException {
            if (v.total >= 0 && position >= v.total) return false;
            boolean on = windowValid > 0 && position == windowStart + windowValid;
            planned = on ? Math.min(planned * 2, MAX) : FIRST;
            int want = v.total >= 0 ? (int) Math.min(planned, v.total - position) : planned;
            if (want <= 0) return false;
            Read r = v.ask(position, want);
            if (r.data.length == 0) return false;
            window = r.data;
            windowStart = position;
            windowValid = r.data.length;
            cursor = 0;
            return true;
        }

        @Override
        public Uri getUri() {
            return uri;
        }

        @Override
        public void close() {
            if (opened) {
                opened = false;
                transferEnded();
            }
        }
    }

    // ---- a page ----

    static final class Page extends NView {
        final String html;

        Page(int id, String html) {
            super(id, 2);
            this.html = html;
        }

        @SuppressLint("SetJavaScriptEnabled")
        @Override
        void make(Context c) {
            web = new WebView(c);
            web.setBackgroundColor(Color.WHITE);
            WebSettings s = web.getSettings();
            s.setJavaScriptEnabled(true);
            s.setAllowFileAccess(false);
            s.setAllowContentAccess(false);
            s.setDomStorageEnabled(false);
            bridge(web);
            web.setWebViewClient(new WebViewClient() {
                @Override
                public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                    return true;
                }

                @Override
                public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                    pageStarted();
                }

                @Override
                public void onPageFinished(WebView view, String url) {
                    pageLoaded();
                    if (state == 0) {
                        state = 1;
                        framed = 1;
                        Host.log("view " + id + ": page loaded (" + bytes + " bytes of HTML)");
                    }
                    pageReady(view);
                    Host.requestFrame();
                }

                @Override
                public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                    if (request.isForMainFrame()) {
                        state = -1;
                        Host.log("view " + id + ": the page failed: " + error.getDescription());
                        tell(-1);
                        Host.requestFrame();
                    }
                }
            });
            bytes = html.getBytes(java.nio.charset.StandardCharsets.UTF_8).length;
            clip.addView(web, new FrameLayout.LayoutParams(0, 0));
            web.loadDataWithBaseURL(null, html, "text/html", "utf-8", null);
        }

        @Override
        void moved() {
            if (web == null) return;
            FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) web.getLayoutParams();
            int l = Math.round(at[0] - at[4]), t = Math.round(at[1] - at[5]);
            int w = Math.round(at[2]), h = Math.round(at[3]);
            if (p.leftMargin != l || p.topMargin != t || p.width != w || p.height != h) {
                p.leftMargin = l;
                p.topMargin = t;
                p.width = w;
                p.height = h;
                web.setLayoutParams(p);
            }
        }

        @Override
        void control(int op, double value) {
            if (op == 21) grabPage();
        }

        @Override
        void destroy() {
            if (web != null) {
                clip.removeView(web);
                web.destroy();
            }
            web = null;
        }
    }

    // ---- a site: a web view whose own host is answered by the app ----

    /**
     * A site served by the app (still.fail's preview of a service, Preview.kt / PreviewWeb.kt): a WebView at a host of
     * its own; every request it makes of that host is said to the app (`siteNext`, on the GL thread), which answers it
     * (`siteHead`, `siteChunk`s, `siteEnd`) from the station through the core while the WebView's thread waits here for
     * the head (a minute at most) and then reads the body as it comes. A body the page lets go of is said (`gone`). A
     * link to anywhere else is not followed, only said (`leave`). Scripts and DOM storage on, as the Android app's.
     * Request bodies are not handed over by a WebView: none here (the Android app's page script carries them). Its
     * cookies are the WebView's (CookieManager, for its host: a request's Cookie from there, an answer's Set-Cookie
     * kept there, as PreviewWeb.kt follow does), so the page's document.cookie is theirs too. A request whose head has
     * not come in `headWaitMs` is said `late` (the app answers it); an answer more of which waits for the page than
     * `backlog` is said `slow` and taken no more (the app ends it).
     */
    static final class Site extends NView {
        static final String HOST = "preview.stillfail.invalid";
        static final Object END = new Object();
        /** Where one cookie ends in a Set-Cookie header holding several (an Expires date's comma is not followed by name=). */
        static final java.util.regex.Pattern COOKIES_JOINED = java.util.regex.Pattern.compile(",\\s*(?=[!#$%&'*+.^_`|~0-9A-Za-z-]+=)");
        final String start;
        final ConcurrentHashMap<Integer, Req> reqs = new ConcurrentHashMap<>();
        /** The app's settings (view_tell 3: ui's site_head_wait_ms, site_backlog_max). */
        volatile long headWaitMs = 60000, backlog = 32L << 20;
        final AtomicInteger nextReq = new AtomicInteger();
        volatile String path, title = "";
        volatile boolean back, forward, loading = true;
        float scale = 1;

        /** One request: its head once the app gives it, its body's pieces as they come, how much of it waits unread. */
        static final class Req {
            final int id;
            boolean headed, failed;
            int status;
            String error;
            final LinkedHashMap<String, String> headers = new LinkedHashMap<>();
            final LinkedBlockingQueue<Object> body = new LinkedBlockingQueue<>();
            final java.util.concurrent.atomic.AtomicLong waiting = new java.util.concurrent.atomic.AtomicLong();
            volatile boolean over;
            /** Its URL, for its cookies. */
            String url;

            Req(int id) {
                this.id = id;
            }
        }

        Site(int id, String start) {
            super(id, 3);
            this.start = start.isEmpty() ? "/" : start;
            this.path = this.start;
        }

        static String pathOf(Uri u) {
            String p = u.getEncodedPath();
            String q = u.getEncodedQuery();
            return (p == null || p.isEmpty() ? "/" : p) + (q != null ? "?" + q : "");
        }

        /** On the WebView's own thread: the request said to the app (its cookies with it), its head waited for. */
        WebResourceResponse answer(WebResourceRequest r) {
            Req q = new Req(nextReq.incrementAndGet());
            q.url = "https://" + HOST + pathOf(r.getUrl());
            reqs.put(q.id, q);
            boolean page = r.isForMainFrame();
            boolean cookied = false;
            org.json.JSONArray hs = new org.json.JSONArray();
            for (Map.Entry<String, String> h : r.getRequestHeaders().entrySet()) {
                if (h.getKey().equalsIgnoreCase("accept") && h.getValue().startsWith("text/html")) page = true;
                if (h.getKey().equalsIgnoreCase("cookie")) cookied = true;
                hs.put(new org.json.JSONArray().put(h.getKey()).put(h.getValue()));
            }
            if (!cookied) {
                String jar = CookieManager.getInstance().getCookie(q.url);
                if (jar != null && !jar.isEmpty()) hs.put(new org.json.JSONArray().put("Cookie").put(jar));
            }
            try {
                String asked = new org.json.JSONObject().put("req", q.id).put("method", r.getMethod())
                        .put("path", pathOf(r.getUrl())).put("headers", hs).put("page", page).toString();
                askApp(() -> said.add(asked));
            } catch (org.json.JSONException e) {
                reqs.remove(q.id);
                return text(500, e.toString());
            }
            // its head waited for as long as the app takes: past headWaitMs the app is told (`late`), which answers it
            long until = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(headWaitMs);
            boolean late = false;
            synchronized (q) {
                while (!q.headed && !q.failed && !closed) {
                    long left = until - System.nanoTime();
                    if (left <= 0 && !late) {
                        late = true;
                        say("{\"late\":" + q.id + "}");
                    }
                    try {
                        q.wait(late ? 250 : Math.min(250, TimeUnit.NANOSECONDS.toMillis(left) + 1));
                    } catch (InterruptedException e) {
                        break;
                    }
                }
            }
            if (!q.headed) {
                reqs.remove(q.id);
                if (!q.failed) say("{\"gone\":" + q.id + "}");
                return text(502, q.failed ? q.error : "closed");
            }
            String type = null;
            for (Map.Entry<String, String> h : q.headers.entrySet()) if (h.getKey().equalsIgnoreCase("content-type")) type = h.getValue();
            if (type == null) type = "application/octet-stream";
            String mime = type.split(";")[0].trim();
            String charset = null;
            java.util.regex.Matcher m = java.util.regex.Pattern.compile("charset=([^;]+)").matcher(type);
            if (m.find()) charset = m.group(1).trim().replace("\"", "");
            int status = q.status >= 200 && q.status <= 599 && (q.status < 300 || q.status > 399) ? q.status : 200;
            boolean encoded = false;
            for (Map.Entry<String, String> h : q.headers.entrySet())
                if (h.getKey().equalsIgnoreCase("content-encoding") && !h.getValue().equalsIgnoreCase("identity")) encoded = true;
            Body body = new Body(this, q);
            body.events = mime.equals("text/event-stream") && !encoded;
            return new WebResourceResponse(mime, charset, status, reason(status), q.headers, body);
        }

        static String reason(int status) {
            return status >= 200 && status < 300 ? "OK" : status == 404 ? "Not Found" : status >= 500 ? "Error" : "Status";
        }

        static WebResourceResponse text(int status, String message) {
            return new WebResourceResponse("text/plain", "utf-8", status, reason(status), new LinkedHashMap<>(),
                    new ByteArrayInputStream((message == null ? "" : message).getBytes(java.nio.charset.StandardCharsets.UTF_8)));
        }

        void head(int req, int status, String headers) {
            Req q = reqs.get(req);
            if (q == null) return;
            try {
                org.json.JSONArray a = new org.json.JSONArray(headers);
                CookieManager jar = CookieManager.getInstance();
                for (int i = 0; i < a.length(); i++) {
                    org.json.JSONArray h = a.getJSONArray(i);
                    String k = h.getString(0), v = h.getString(1);
                    q.headers.put(k, q.headers.containsKey(k) ? q.headers.get(k) + ", " + v : v);
                    // the service's cookies kept by the WebView (several may come joined in one header: each kept)
                    if (k.equalsIgnoreCase("set-cookie")) for (String one : COOKIES_JOINED.split(v)) jar.setCookie(q.url, one);
                }
            } catch (org.json.JSONException e) {
                Host.log("view " + id + ": a head's headers unread: " + e);
            }
            synchronized (q) {
                q.status = status;
                q.headed = true;
                q.notifyAll();
            }
        }

        void chunk(int req, byte[] data) {
            Req q = reqs.get(req);
            if (q == null || q.over || data.length == 0) return;
            // more of it waiting for the page than backlog: the app told (it ends it), none more taken
            if (q.waiting.addAndGet(data.length) > backlog) {
                q.over = true;
                say("{\"slow\":" + q.id + "}");
                return;
            }
            q.body.add(data);
        }

        void end(int req, String error) {
            Req q = reqs.remove(req);
            if (q == null) return;
            synchronized (q) {
                if (!q.headed) {
                    q.failed = true;
                    q.error = error.isEmpty() ? "no answer" : error;
                    q.notifyAll();
                    return;
                }
            }
            q.body.add(error.isEmpty() ? END : new IOException(error));
        }

        String state() {
            try {
                return new org.json.JSONObject().put("path", path).put("back", back).put("forward", forward)
                        .put("loading", loading).put("title", title).put("cookies", true).toString();
            } catch (org.json.JSONException e) {
                return null;
            }
        }

        /** Where the page is now, its history, whether it loads: on the main thread. */
        void moved(WebView w, Boolean busy) {
            String url = w.getUrl();
            if (url != null) {
                Uri u = Uri.parse(url);
                path = HOST.equals(u.getHost()) ? pathOf(u) : url;
            }
            back = w.canGoBack();
            forward = w.canGoForward();
            if (busy != null) loading = busy;
            String t = w.getTitle();
            title = t == null ? "" : t;
            Host.requestFrame();
        }

        @SuppressLint("SetJavaScriptEnabled")
        @Override
        void make(Context c) {
            web = new WebView(c);
            web.setBackgroundColor(Color.WHITE);
            WebSettings st = web.getSettings();
            st.setJavaScriptEnabled(true);
            st.setDomStorageEnabled(true);
            st.setAllowFileAccess(false);
            st.setAllowContentAccess(false);
            CookieManager.getInstance().setAcceptCookie(true);
            bridge(web);
            web.setWebViewClient(new WebViewClient() {
                @Override
                public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                    Uri url = request.getUrl();
                    if (HOST.equals(url.getHost()) && ("https".equals(url.getScheme()) || "http".equals(url.getScheme()))) return false;
                    // a frame in the page shows what it likes; the page itself stays the site
                    if (!request.isForMainFrame()) return false;
                    if ("about".equals(url.getScheme())) return false;
                    String sc = url.getScheme();
                    if ("data".equals(sc) || "blob".equals(sc) || "javascript".equals(sc)) return true;
                    try {
                        say(new org.json.JSONObject().put("leave", url.toString()).toString());
                    } catch (org.json.JSONException ignored) {
                    }
                    return true;
                }

                @Override
                public void doUpdateVisitedHistory(WebView view, String url, boolean isReload) {
                    moved(view, null);
                }

                @Override
                public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                    pageStarted();
                    moved(view, true);
                }

                @Override
                public void onPageFinished(WebView view, String url) {
                    pageLoaded();
                    if (state == 0) {
                        state = 1;
                        framed = 1;
                        Host.log("view " + id + ": site page loaded (" + path + ")");
                    }
                    pageReady(view);
                    moved(view, false);
                }

                @Override
                public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                    if (request.isForMainFrame() && state == 0) {
                        Host.log("view " + id + ": the site's page failed: " + error.getDescription());
                        tell(-1);
                    }
                }

                @Override
                public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                    return HOST.equals(request.getUrl().getHost()) ? answer(request) : null;
                }
            });
            clip.addView(web, new FrameLayout.LayoutParams(0, 0));
            web.loadUrl("https://" + HOST + start);
        }

        @Override
        void moved() {
            if (web == null) return;
            FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) web.getLayoutParams();
            int l = Math.round(at[0] - at[4]), t = Math.round(at[1] - at[5]);
            // laid out at its rect over its scale, drawn at its scale from its top left
            int w = Math.round(at[2] / scale), h = Math.round(at[3] / scale);
            if (p.leftMargin != l || p.topMargin != t || p.width != w || p.height != h) {
                p.leftMargin = l;
                p.topMargin = t;
                p.width = w;
                p.height = h;
                web.setLayoutParams(p);
            }
            web.setPivotX(0);
            web.setPivotY(0);
            web.setScaleX(scale);
            web.setScaleY(scale);
        }

        @Override
        void control(int op, double value) {
            if (web == null) return;
            switch (op) {
                case 5: if (web.canGoBack()) web.goBack(); break;
                case 6: if (web.canGoForward()) web.goForward(); break;
                case 7: web.reload(); break;
                case 8:
                    if (value > 0) {
                        scale = (float) value;
                        moved();
                    }
                    break;
                case 21: grabPage(); break;
                default: break;
            }
        }

        @Override
        void destroy() {
            for (Req q : reqs.values()) {
                synchronized (q) {
                    q.failed = true;
                    q.error = "closed";
                    q.notifyAll();
                }
                q.body.add(END);
            }
            reqs.clear();
            if (web != null) {
                clip.removeView(web);
                web.destroy();
            }
            web = null;
        }
    }

    /** A request's body as the app sends it, read by the WebView; let go of before its end, the app is told. */
    static final class Body extends InputStream {
        final Site site;
        final Site.Req q;
        byte[] cur;
        int at;
        boolean ended, told;
        /** An event stream (text/event-stream): what comes goes to the page at once (PreviewWeb.kt Chunks). */
        boolean events, gave;
        byte lastByte;

        Body(Site site, Site.Req q) {
            this.site = site;
            this.q = q;
        }

        private boolean next() throws IOException {
            while (cur == null || at >= cur.length) {
                if (ended) return false;
                Object o;
                try {
                    // as long as the service takes (a long poll, an event stream): the page lets it go when it will
                    o = q.body.take();
                } catch (InterruptedException e) {
                    throw new InterruptedIOException();
                }
                if (o == Site.END) {
                    ended = true;
                    return false;
                }
                if (o instanceof IOException) {
                    ended = true;
                    throw (IOException) o;
                }
                cur = (byte[]) o;
                at = 0;
                q.waiting.addAndGet(-cur.length);
            }
            return true;
        }

        @Override
        public int read() throws IOException {
            if (!next()) return -1;
            return cur[at++] & 0xff;
        }

        @Override
        public int read(byte[] b, int off, int len) throws IOException {
            if (len == 0) return 0;
            // The WebView reads on until its buffer is full before it hands anything to the page. An event stream's
            // events are to come as they are sent: with nothing more here yet, after a piece that ended its line, the
            // rest of the buffer is filled with a comment (which the page's EventSource passes over).
            if (events && gave && lastByte == '\n' && (cur == null || at >= cur.length) && q.body.isEmpty() && !ended) {
                gave = false;
                if (len == 1) {
                    b[off] = '\n';
                    return 1;
                }
                b[off] = ':';
                java.util.Arrays.fill(b, off + 1, off + len - 1, (byte) ' ');
                b[off + len - 1] = '\n';
                return len;
            }
            if (!next()) return -1;
            int n = Math.min(len, cur.length - at);
            System.arraycopy(cur, at, b, off, n);
            at += n;
            gave = true;
            lastByte = b[off + n - 1];
            return n;
        }

        @Override
        public int available() {
            return cur == null ? 0 : cur.length - at;
        }

        @Override
        public void close() {
            if (!ended && !told) {
                told = true;
                site.reqs.remove(q.id);
                site.say("{\"gone\":" + q.id + "}");
            }
            ended = true;
        }
    }
}
