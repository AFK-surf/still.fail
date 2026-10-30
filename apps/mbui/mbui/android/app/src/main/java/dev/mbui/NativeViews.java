package dev.mbui;

import android.annotation.SuppressLint;
import android.content.ContentValues;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.PorterDuff;
import android.graphics.SurfaceTexture;
import android.media.MediaDataSource;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.opengl.GLES30;
import android.provider.MediaStore;
import android.view.Choreographer;
import android.view.Surface;
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
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.SeekParameters;
import androidx.media3.exoplayer.source.ProgressiveMediaSource;
import androidx.media3.extractor.DefaultExtractorInput;
import androidx.media3.extractor.DiscardingTrackOutput;
import androidx.media3.extractor.Extractor;
import androidx.media3.extractor.ExtractorInput;
import androidx.media3.extractor.ExtractorOutput;
import androidx.media3.extractor.PositionHolder;
import androidx.media3.extractor.SeekMap;
import androidx.media3.extractor.TrackOutput;
import androidx.media3.extractor.mp4.Mp4Extractor;
import androidx.media3.extractor.text.SubtitleParser;

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
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Native views in the canvas (src/host/host_native.mbt `view_*`, src/ui/native.mbt). Each draws into a picture of its
 * own (Picture: a SurfaceTexture of the app's GL context), which the canvas draws where the app paints the view (its
 * instance of kind 9, whose image is MB_VIEW_TEX + its id: android_host.c), in the same frame as what is around it:
 * the system never puts a view on the screen itself. What the app paints after the view draws over it, a clip it is
 * painted in cuts it, and it moves with a list as the list moves, in step to the frame; moved, it costs nothing but
 * that frame (no window drawn again, no page composited again).
 *
 * They live in `layer`, a FrameLayout over the MBView in the view tree, so a WebView takes the touches on it and is
 * laid out, attached and shown as the system's views are; on the screen the MBView's surface is over it, and the
 * views draw nothing in the window. Each sits in a frame (TouchFrame) put where it shows once it rests (moving with a
 * list, only its picture moves: place), moved by its translation, for the touches on it: a page's or a site's frame is
 * its content's rect, the part of it seen its `seen`; a video's is its clip rect.
 *
 * Kind 1, a video: Media3's ExoPlayer onto its picture's surface, reading the file through the app (ViewSource:
 * ranged reads the app answers through the core, `station.file.part` or `drive.read`), never from a file or a URL of
 * its own.
 * Kind 4, a stream's picture (StreamLayer): not drawn in the canvas but on a layer of the system's under it, where
 * the canvas is cleared for it (android_host.c's views_under).
 * Kind 2, a page of HTML in a WebView, as still.fail's Android app shows an HTML file (FilePreview.kt HtmlPage):
 * scripts on, no file or content access, no DOM storage, no link followed. A page's and a site's frame draws its
 * WebView into its picture (TouchFrame.draw) as the WebView changes, not as it moves; a page taller than a picture can
 * be, a part of it at a time (Page).
 *
 * Called on the GL thread (MoonBit's); views are made and moved on the main thread.
 */
@OptIn(markerClass = UnstableApi.class)
final class NativeViews {
    static FrameLayout layer;
    static final ConcurrentHashMap<Integer, NView> views = new ConcurrentHashMap<>();
    static final AtomicInteger next = new AtomicInteger();

    /**
     * One read asked of the app (a video's run of blocks, Video.bytesAt): its bytes as they come, the app answering it
     * in pieces until its last answer; what its readers take of it as soon as it is here. Its monitor guards it: a
     * piece is put in, and `got` moved on, under it.
     */
    static final class Read {
        final int id;
        final long offset;
        final int length;
        /** the blocks it brings: the first, how many */
        final int block, blocks;
        final byte[] data;
        /** how many of its bytes have come; when the last of them came (System.nanoTime) */
        volatile int got;
        long heard;
        /** its last answer came; it could not be read (the app said so, or nothing came for STALL_NS); let go of */
        volatile boolean done;
        boolean failed, gone;
        /** the readers whose run it is (Video.Pace.read), under the view's keptLock */
        int users;

        Read(int id, long offset, int length, int block, int blocks) {
            this.id = id;
            this.offset = offset;
            this.length = length;
            this.block = block;
            this.blocks = blocks;
            this.data = new byte[length];
            this.heard = System.nanoTime();
        }

        /**
         * Up to `len` of its bytes at `p` into `buf` once they have come: how many; 0 when it ended short of `p` (its
         * last answer came, or it was let go of, before); an error when it could not be read. Waits on the reader's
         * thread; the player's reader (`pace.player`) waiting is the view's waiting for its bytes (Video.bytesWaited).
         */
        synchronized int take(Video v, Video.Pace pace, long p, byte[] buf, int off, int len) throws IOException {
            int at = (int) (p - offset);
            boolean counted = false;
            try {
                while (got <= at && !done) {
                    if (v.closed) throw new InterruptedIOException("view " + v.id + " closed");
                    if (pace.player && !counted) {
                        counted = true;
                        v.bytesWaited.incrementAndGet();
                        v.stood();
                    }
                    wait(250);
                }
            } catch (InterruptedException e) {
                throw new InterruptedIOException();
            } finally {
                if (counted) {
                    v.bytesWaited.decrementAndGet();
                    v.stood();
                }
            }
            if (got > at) {
                int k = Math.min(len, got - at);
                System.arraycopy(data, at, buf, off, k);
                return k;
            }
            if (failed) throw new IOException("view " + v.id + ": the read at " + offset + " failed");
            return 0;
        }
    }

    static class NView {
        final int id, kind;
        /** What it is made in: the activity whose layer it is in, switched as it moves to another's (moveTo). */
        android.content.MutableContextWrapper context;
        TouchFrame clip;
        View content;
        /** What it shows, drawn by the canvas (made on the GL thread as it opens). */
        Picture picture;
        volatile boolean closed;
        // how it stands, for info (the GL thread reads these)
        volatile int state;
        volatile double duration = -1, position, playing, nw, nh, bytes, framed, buffering, buffered, ended;
        // placed: x y w h cx0 cy0 cx1 cy1, the content's roundest corner, the part of the content its frame is (its
        // top, from the content's, and its height: partOf), each of its corners (top left, then round it), in
        // pixels; shown
        final float[] at = new float[15];
        /** Where it was told to go before it was made (made once the window has had the focus): put there as it is. */
        float[] pendingTo;
        boolean pendingShown;
        /**
         * (GL thread) Where it was last told to go (device pixels, as `at`) and whether shown; moved there in the frame
         * being drawn; told and not put there yet (it moves with what holds it: its frame follows once it rests, settle).
         */
        float[] toldTo;
        boolean toldShown, movedNow;
        volatile boolean unsettled;
        /** Where it was last told to go, for the main thread (whether its frame is there: TouchFrame). */
        volatile float[] lastTo;
        boolean shown;
        private boolean told;
        // (main thread) placed once where told and shown; its host done with it (ready or failed); its first picture
        // since on the display said (VIEWDRAWN: scripts/host_contract.sh android views takes its picture then)
        private boolean placedOnce, doneOnce, drawnSaid;

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
            Host.main.post(() -> {
                doneOnce = true;
                drawnWhenBoth();
            });
            stood();
        }

        /** (GL thread) How it stands (info's numbers and its state) as the app was last told, and as it is now. */
        private final double[] stoodSaid = new double[10], stoodNow = new double[10];
        private int stoodState = Integer.MIN_VALUE;
        /** Whether a look at how it stands is on its way to the GL thread. */
        private final AtomicBoolean stoodAsked = new AtomicBoolean();

        /**
         * How it stands may have changed (any thread here): looked at on the GL thread, between frames, and the app told
         * where it did (android_host.c's mb_host_set_outside: kind 13, src/ui/hostcall.mbt's outside_stood), which reads
         * it then, not each frame. Asked as often as anything changes: told only where something did.
         */
        void stood() {
            MBView mv = Host.view;
            if (closed || mv == null || !stoodAsked.compareAndSet(false, true)) return;
            mv.toGL(() -> {
                stoodAsked.set(false);
                if (closed) return;
                int st = info(id, stoodNow);
                if (st == stoodState && java.util.Arrays.equals(stoodNow, stoodSaid)) return;
                stoodState = st;
                System.arraycopy(stoodNow, 0, stoodSaid, 0, stoodNow.length);
                Native.outside(Native.OUTSIDE_STOOD, id, 0);
            });
        }

        /** (main thread) How many parts of it its frame has been since its first (a tall page's, Page.moved). */
        int partsShown;

        /**
         * A new part of it its frame is (main thread): a picture of that part said once it is on the display (VIEWDRAWN
         * id part n).
         */
        void drawnAgain() {
            partsShown++;
            drawnSaid = false;
            drawnWhenBoth();
        }

        /**
         * Once placed and done: the canvas's frame with a picture of it from then (a page's drawn again now; a video's
         * the frame it shows) said once it is on the display (VIEWDRAWN id, Picture.latch), once (a tall page's, once
         * for each part of it its frame is).
         */
        void drawnWhenBoth() {
            if (!placedOnce || !doneOnce || drawnSaid || clip == null || closed || picture == null) return;
            drawnSaid = true;
            picture.sayPart = partsShown;
            if (kind == 1) {
                picture.sayAfter = Long.MIN_VALUE;
            } else {
                clip.sayNext = true;
                clip.invalidate();
            }
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
         * callback: it comes for a view that is drawn, and one that shows is), at once when it does not show (nothing of
         * it is on the screen to wait for).
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
        }

        void make(Context c) {}

        /** Whether its frame is where it was last told to go (main thread): a finger down on it is the view's then. */
        boolean where() {
            float[] to = lastTo;
            if (to == null) return true;
            for (int i = 0; i < 8; i++) if (Math.abs(at[i] - to[i]) >= 0.5f) return false;
            return true;
        }

        /**
         * Its picture made anew (a new GL context: Picture.make), on the main thread before the old one's surface is
         * let go of: a page's or a site's frame drawn again on it, at its size.
         */
        void pictureAnew() {
            picture.w = picture.h = 0;
            if (clip != null) clip.invalidate();
        }

        void moved() {}

        /**
         * The part of its content its frame is, and so its picture (GL thread, as it is told where it goes): `to`'s
         * last two, from where it is to go (`to`) and the part it was (`was`, null at first). All of it; a tall page's
         * is a part of it (Page.partOf).
         */
        void partOf(float[] to, float[] was, boolean shown) {
            to[9] = 0;
            to[10] = to[3];
        }

        /**
         * The part of its content a picture of its frame `h` pixels tall is, drawn now (main thread): its top and its
         * height, of the content's (0 to 1). All of it but a tall page's (Page.drawnPart).
         */
        float[] drawnPart(int h) {
            return WHOLE;
        }

        /** Whether a picture drawn now is the part of its content its frame is (main thread): a page scrolled to it. */
        boolean partDrawn() {
            return true;
        }

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
     * The frame a view sits in, which takes a finger as the app says (view_tell 2, ui's NativeView::touch): its view's
     * ("all"); the canvas's (MBView: "through", none of it to the view); the view's until a second finger comes down
     * ("pinch") or the finger has gone further up or down than across past the slop ("vertical"; a finger that went
     * sideways past it first stays the view's to its end), the canvas's from there: the view told the touch is called
     * off, the canvas given it from where it went down. A finger that goes down where the app draws something that
     * takes a press over the view (view_tell 4: `covers`), or outside the part of it seen (`seen`), is the canvas's.
     *
     * It draws nothing in the window: a page's or a site's draws itself, its WebView in it, into its view's picture
     * instead, whole (the part seen is the canvas's to cut), each time something in it changes (Flutter's
     * PlatformViewWrapper draws a platform view so); a video's player draws into its picture itself.
     */
    static final class TouchFrame extends FrameLayout {
        final NView owner;
        String mode = "all";
        /** The part of it seen (its frame's pixels), null for all of it: a finger down outside is the canvas's. */
        android.graphics.Rect seen;
        /** Its next picture's frame said once it is on the display (NView.drawnWhenBoth). */
        boolean sayNext;
        /** Where the app draws what takes a press over the view: x0 y0 x1 y1 …, the canvas's pixels. */
        float[] covers = new float[0];
        float slop;
        float downX, downY;
        boolean taken;
        /** The finger went sideways past the slop first (vertical): the page's to the end of the touch. */
        boolean sideways;

        TouchFrame(Context c, NView owner) {
            super(c);
            this.owner = owner;
            // (drawn by draw(), below, not only its children's dispatchDraw)
            setWillNotDraw(false);
        }

        @Override
        public void draw(Canvas canvas) {
            NView v = owner;
            Picture p = v.picture;
            if (v.kind == 1 || v.closed || p == null) return;
            SurfaceTexture st = p.st;
            Surface s = p.surface;
            int w = getWidth(), h = getHeight();
            if (st == null || s == null || !s.isValid() || w <= 0 || h <= 0) return;
            if (w != p.w || h != p.h) st.setDefaultBufferSize(w, h);
            // (the part of its content this picture is, as its page is scrolled now: Page.partOf)
            float[] part = v.drawnPart(h);
            Canvas c;
            try {
                c = s.lockHardwareCanvas();
            } catch (RuntimeException e) {
                Host.log("view " + v.id + ": its picture not drawn: " + e);
                return;
            }
            try {
                c.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR);
                super.draw(c);
            } finally {
                p.w = w;
                p.h = h;
                p.drawn(System.nanoTime(), part);
                // (this frame's time, which its buffer's is not before: a frame from then on said, Picture.latch; a tall
                // page's once it shows the part asked)
                if (sayNext && v.partDrawn()) {
                    sayNext = false;
                    p.sayAfter = System.nanoTime();
                }
                s.unlockCanvasAndPost(c);
            }
        }

        // (something in it changed, the WebView's page or how it is laid out or scaled: its picture drawn again; the
        // window would draw only the view that changed, not this frame)
        @Override
        public void onDescendantInvalidated(View child, View target) {
            super.onDescendantInvalidated(child, target);
            invalidate();
        }

        @Override
        public boolean dispatchTouchEvent(MotionEvent e) {
            // (through: none of it is the view's; MBView, under this layer, is given it by the window)
            if (mode.equals("through")) return false;
            // (a finger down while its view moves, its frame not where the view shows yet: the canvas's, as what
            // moves under a finger is the list's to stop)
            if (e.getActionMasked() == MotionEvent.ACTION_DOWN && !owner.where()) return false;
            // (a finger down on what is not seen of it is not the view's: the window gives it to MBView)
            if (e.getActionMasked() == MotionEvent.ACTION_DOWN) {
                android.graphics.Rect r = seen;
                if (r != null && !r.contains((int) e.getX(), (int) e.getY())) return false;
            }
            // (down under what the app draws over the view: the canvas's, the rest of the touch with it)
            if (e.getActionMasked() == MotionEvent.ACTION_DOWN && covered(e)) return false;
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

        /** Whether the finger is where the app draws something that takes a press over the view. */
        private boolean covered(MotionEvent e) {
            MBView v = Host.view;
            if (v == null || covers.length < 4) return false;
            float x = e.getX() + getLeft() + getTranslationX() - v.getLeft(), y = e.getY() + getTop() + getTranslationY() - v.getTop();
            for (int j = 0; j + 3 < covers.length; j += 4)
                if (x >= covers[j] && x < covers[j + 2] && y >= covers[j + 1] && y < covers[j + 3]) return true;
            return false;
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
            m.offsetLocation(getLeft() + getTranslationX() - v.getLeft(), getTop() + getTranslationY() - v.getTop());
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
        if (kind < 1 || kind > 4) return 0;
        int id = next.incrementAndGet();
        // a stream's picture on a layer of its own under the canvas (kind 4, `arg` the stream's id): StreamLayer's
        if (kind == 4) return StreamLayer.open(id, arg) ? id : 0;
        NView v = kind == 1 ? new Video(id, arg) : kind == 2 ? new Page(id, arg) : new Site(id, arg);
        // (its picture's SurfaceTexture is of the GL context, made here, on its thread, before the view is)
        v.picture = new Picture(id);
        v.picture.make();
        views.put(id, v);
        Host.log("view " + id + ": open " + (kind == 1 ? "video " + arg : kind == 2 ? "page of " + arg.length() + " characters" : "site at " + arg));
        Host.main.post(() -> {
            if (kind == 3 && cookiesClearing) {
                afterCookies.add(() -> make(v, kind));
                return;
            }
            // a WebView's first, made before the window first had the focus: the browser's engine starting on the main
            // thread (seconds on an emulator) held the window's FocusEvent past the input timeout, an ANR, the app
            // ended (mbui-host-android's site contract, 39781713658): made once that event is handled
            if (kind != 1 && !focusedOnce) {
                afterFocus.add(() -> make(v, kind));
                return;
            }
            make(v, kind);
        });
        return id;
    }

    /** Whether the window has had the focus since the app started (main thread). */
    static boolean focusedOnce;

    /** Views waiting for that (main thread). */
    static final java.util.ArrayList<Runnable> afterFocus = new java.util.ArrayList<>();

    /** The window has the focus (MainActivity.onWindowFocusChanged): the views waiting for it made after this event. */
    static void focused() {
        if (focusedOnce) return;
        focusedOnce = true;
        Host.main.post(() -> {
            for (Runnable r : afterFocus) r.run();
            afterFocus.clear();
        });
    }

    /** A view made and put in the layer (main thread). */
    private static void make(NView v, int kind) {
        if (v.closed) return;
        if (layer == null) {
            v.tell(-1);
            return;
        }
        v.context = new android.content.MutableContextWrapper(layer.getContext());
        v.clip = new TouchFrame(v.context, v);
        v.clip.setClipChildren(true);
        v.clip.setBackgroundColor(kind == 1 ? Color.BLACK : kind == 2 ? Color.WHITE : Color.TRANSPARENT);
        v.clip.setVisibility(View.GONE);
        v.make(v.context);
        layer.addView(v.clip, new FrameLayout.LayoutParams(0, 0));
        if (v.pendingTo != null) {
            put(v, v.pendingTo, v.pendingShown);
            v.pendingTo = null;
        }
    }

    /**
     * Where the app says view `id` shows (GL thread, as the frame is drawn). Moved only (as large, as round, still shown;
     * cut anew or not: a list scrolled under it, its edge), nothing is done for it now: the canvas draws its picture
     * there in this frame, as cut as it is, and its frame, which takes the touches on it, follows once it rests
     * (framed): a move of a system view makes the window draw again, each frame of a scroll. Shown, hidden or sized
     * anew, or a tall page's part of it moved on (partOf), it is put there at once.
     */
    static void place(int id, float x, float y, float w, float h, float cx0, float cy0, float cx1, float cy1,
                      float r0, float r1, float r2, float r3, boolean shown) {
        NView v = views.get(id);
        if (v == null) {
            StreamLayer.place(id, x, y, w, h, cx0, cy0, cx1, cy1, shown);
            return;
        }
        float d = Host.view.density;
        float most = Math.max(Math.max(r0, r1), Math.max(r2, r3));
        float[] to = {x * d, y * d, w * d, h * d, cx0 * d, cy0 * d, cx1 * d, cy1 * d, most * d, 0, 0,
                r0 * d, r1 * d, r2 * d, r3 * d};
        float[] was = v.toldTo;
        v.partOf(to, was, shown);
        boolean moved = was != null && shown && v.toldShown && Math.abs(to[2] - was[2]) < 0.5f
                && Math.abs(to[3] - was[3]) < 0.5f && Math.abs(to[8] - was[8]) < 0.5f
                && Math.abs(to[9] - was[9]) < 0.5f && Math.abs(to[10] - was[10]) < 0.5f
                && Math.abs(to[11] - was[11]) < 0.5f && Math.abs(to[12] - was[12]) < 0.5f
                && Math.abs(to[13] - was[13]) < 0.5f && Math.abs(to[14] - was[14]) < 0.5f;
        v.toldTo = to;
        v.toldShown = shown;
        v.lastTo = to;
        if (moved) {
            v.movedNow = true;
            v.unsettled = true;
            return;
        }
        v.unsettled = false;
        tellPut(v, to, shown);
    }

    /**
     * A frame drawn (MBView, GL thread): `more` whether another follows at once (the app asks for one). A view moved in
     * it rests once a frame passes that does not move it, or none follows: its frame put where it shows.
     */
    static void framed(boolean more) {
        for (NView v : views.values()) {
            if (!v.unsettled) continue;
            if (v.movedNow) {
                v.movedNow = false;
                if (more) continue;
            }
            v.unsettled = false;
            tellPut(v, v.toldTo, v.toldShown);
        }
    }

    /** View `v` put at `to`, shown or not, on the main thread (once made: where it is to go kept until then). */
    private static void tellPut(NView v, float[] to, boolean shown) {
        Host.main.post(() -> {
            if (v.closed) return;
            if (v.clip == null) {
                v.pendingTo = to;
                v.pendingShown = shown;
                return;
            }
            put(v, to, shown);
        });
    }

    /** View `v` (made) put at `to` (device pixels: its content's rect, its clip, its corners), shown or not (main thread). */
    private static void put(NView v, float[] to, boolean shown) {
        {
            int id = v.id;
            boolean same = v.shown == shown;
            for (int i = 0; i < v.at.length && same; i++) same = Math.abs(v.at[i] - to[i]) < 0.5f;
            if (same) return;
            System.arraycopy(to, 0, v.at, 0, v.at.length);
            v.shown = shown;
            int l = Math.round(to[4]), t = Math.round(to[5]);
            int cw = Math.max(0, Math.round(to[6]) - l), ch = Math.max(0, Math.round(to[7]) - t);
            // The frame moved by its translation, never by its margins: a layout each frame a list scrolls (a page
            // in a message) dropped frames. A page's or a site's frame is its content's rect (a tall page's, the part
            // of it near what is seen: partOf), the part of it within the clip `seen`, so only a new size lays it out
            // again (and draws its picture again); a video's is the clip's. Moved, nothing of it is drawn again: the
            // canvas draws its picture where the app paints it.
            boolean whole = v.kind != 1;
            int fx = whole ? Math.round(to[0]) : l, fy = whole ? Math.round(to[1]) + Math.round(to[9]) : t;
            int fw = whole ? Math.max(0, Math.round(to[2])) : cw, fh = whole ? Math.max(0, Math.round(to[10])) : ch;
            FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) v.clip.getLayoutParams();
            if (p.leftMargin != 0 || p.topMargin != 0 || p.width != fw || p.height != fh) {
                p.leftMargin = 0;
                p.topMargin = 0;
                p.width = fw;
                p.height = fh;
                v.clip.setLayoutParams(p);
            }
            v.clip.setTranslationX(fx);
            v.clip.setTranslationY(fy);
            v.clip.seen = whole ? new android.graphics.Rect(l - fx, t - fy, l - fx + cw, t - fy + ch) : null;
            v.clip.setVisibility(shown && cw > 0 && ch > 0 ? View.VISIBLE : View.GONE);
            v.moved();
            if (shown) {
                // where it is now, in device pixels (scripts/host_contract.sh HOST views compares it with VIEWTOLD),
                // on a run's draw log only: not at each step of a scroll
                if (drawLog()) Host.log(String.format(java.util.Locale.ROOT,
                        "VIEWAT %d %.4f %.4f %.4f %.4f %d %d %d %d %.4f %.4f %.4f %.4f %.4f", id, to[0], to[1], to[2],
                        to[3], l, t, l + cw, t + ch, to[8], to[11], to[12], to[13], to[14]));
                v.placedOnce = true;
                v.drawnWhenBoth();
            }
        }
    }

    /** Whether the run keeps a draw log (MBUI_DRAW_LOG): where each view is put said there. */
    static boolean drawLog() {
        return "1".equals(android.system.Os.getenv("MBUI_DRAW_LOG"));
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
        if (v == null) {
            StreamLayer.close(id);
            return;
        }
        v.closed = true;
        Host.log("view " + id + ": closed (" + (long) v.bytes + " bytes given)");
        // (no frame draws its picture from now on; its surface let go once nothing draws on it)
        Picture p = v.picture;
        int ext = p.drop();
        Host.main.post(() -> {
            v.destroy();
            // out of whichever layer it is in (an activity's other than the one resumed now, not yet moved)
            if (v.clip != null && v.clip.getParent() != null) ((android.view.ViewGroup) v.clip.getParent()).removeView(v.clip);
            p.letGo(ext);
        });
    }

    // ---- the views' pictures ----

    /** The texture the canvas draws view `id`'s picture with now (0: none; android_host.c's MB_VIEW_TEX + id). */
    static native void texture(int id, int tex);

    /**
     * The part of view `id`'s content its picture is now: its top and its height, of the content's (0 to 1; all of it
     * but a tall page's, Page.partOf). The canvas draws the picture there, and nothing of the content outside it.
     */
    static native void part(int id, float top, float height);

    /** All of a view's content. */
    static final float[] WHOLE = {0f, 1f};

    /** The largest texture the GL context takes, in pixels a side (GL thread, as the first picture is made). */
    static volatile int textureMost;

    /** Pictures done with, their SurfaceTextures let go of on the GL thread as it next latches. */
    private static final ConcurrentLinkedQueue<Object[]> doneWith = new ConcurrentLinkedQueue<>();

    /**
     * As a frame begins (MBView.onDrawFrame, GL thread): each view's new picture, if any, latched and drawn into its
     * texture, for the frame to draw it where it shows; the SurfaceTextures done with let go.
     */
    static void latch() {
        for (Object[] d; (d = doneWith.poll()) != null; ) {
            ((SurfaceTexture) d[0]).release();
            int ext = (Integer) d[1];
            if (ext != 0) GLES30.glDeleteTextures(1, new int[] {ext}, 0);
        }
        for (NView v : views.values()) {
            Picture p = v.picture;
            if (p != null) p.latch();
        }
    }

    /**
     * A new GL context (android_host.c images_lost, GL thread): each picture made anew in it, its producer drawing on
     * the new one (a page's frame drawn again; a video's player put on it).
     */
    static void lost() {
        // (the copy into a picture's texture made anew too: Streams' own, there may be no stream to say so)
        Streams.blitLost();
        for (NView v : views.values()) {
            Picture p = v.picture;
            if (p == null || v.closed) continue;
            SurfaceTexture oldSt = p.st;
            Surface oldSurface = p.surface;
            p.make();
            Host.main.post(() -> {
                if (!v.closed) v.pictureAnew();
                oldSurface.release();
                doneWith.add(new Object[] {oldSt, 0});
                Host.requestFrame();
            });
        }
    }

    /**
     * What a view shows, drawn by the canvas where the app paints the view (its instance of kind 9, whose image is
     * MB_VIEW_TEX + its id), in the frame with what is around it. Its producer (a page's or a site's frame,
     * TouchFrame.draw; a video's player) draws on `surface`, a SurfaceTexture of the app's GL context; the frames it
     * sends are latched as the canvas's next frame begins (latch), the last drawn into a plain texture of its size, as
     * a stream's frame is (Streams.blitFrame). The canvas is asked only to draw its last frame again with it
     * (MBView.pictureFrame), not the app for a frame of its own: the view's place is the same.
     */
    static final class Picture {
        final int id;
        /** Its SurfaceTexture and the surface on it its producer draws on (made on the GL thread, read on any). */
        volatile SurfaceTexture st;
        volatile Surface surface;
        // (GL thread) the external texture under the SurfaceTexture; the plain texture drawn, and its size
        private int ext, tex, texW, texH;
        /**
         * The frames its SurfaceTexture has said have come, and those of them latched (GL thread). A frame sent before
         * the one before it was latched takes its place unsaid (BufferQueue's onFrameReplaced): latched, the newest.
         */
        final AtomicInteger arrived = new AtomicInteger();
        private int latched;
        /** The size of the frames its producer sends (pixels): a page's frame's, a video's picture's. */
        volatile int w, h;
        /**
         * Once a frame of this time or after (its buffer's, System.nanoTime's clock) is latched, the canvas's frame
         * showing it said on the display (VIEWDRAWN; Long.MAX_VALUE: not asked); the time it was latched at.
         */
        volatile long sayAfter = Long.MAX_VALUE;
        /** The part of it (NView.partsShown) the frame said shows: 0, its first. */
        volatile int sayPart;
        private long stamp;
        /**
         * The part of its content each frame sent was (TouchFrame.draw), with when it was sent (System.nanoTime, before
         * its buffer's time), the oldest first; the part the frame latched last is (GL thread).
         */
        private final java.util.ArrayDeque<Sent> sent = new java.util.ArrayDeque<>();
        private float[] latchedPart = WHOLE;

        private static final class Sent {
            final long at;
            final float[] part;

            Sent(long at, float[] part) {
                this.at = at;
                this.part = part;
            }
        }

        Picture(int id) {
            this.id = id;
        }

        /** A frame sent now (`at`), the part `part` of its content (main thread, as it is drawn). */
        void drawn(long at, float[] part) {
            synchronized (sent) {
                sent.addLast(new Sent(at, part));
                while (sent.size() > 16) sent.removeFirst();
            }
        }

        /**
         * The part of its content the frame latched is, by its buffer's time (GL thread): the last sent by then, as the
         * one sent after it may be sent before it is latched.
         */
        private float[] partAt(long stamp) {
            synchronized (sent) {
                while (!sent.isEmpty() && sent.peekFirst().at <= stamp) latchedPart = sent.removeFirst().part;
            }
            return latchedPart;
        }

        /** Its SurfaceTexture made (anew) on a new external texture of the context there is (GL thread). */
        void make() {
            if (textureMost == 0) {
                int[] most = {0};
                GLES30.glGetIntegerv(GLES30.GL_MAX_TEXTURE_SIZE, most, 0);
                textureMost = most[0] > 0 ? most[0] : 2048;
            }
            ext = Streams.external();
            SurfaceTexture t = new SurfaceTexture(ext);
            arrived.set(0);
            latched = 0;
            // (said on the main thread; one from a SurfaceTexture let go is not this one's)
            t.setOnFrameAvailableListener(x -> {
                if (st != t) return;
                arrived.incrementAndGet();
                MBView m = Host.view;
                if (m != null) m.pictureFrame();
            }, Host.main);
            st = t;
            surface = new Surface(t);
            if (tex != 0) texture(id, 0);
            tex = 0;
            texW = texH = 0;
        }

        /** Its frames come since the last latched, the last of them drawn into its texture (GL thread). */
        void latch() {
            SurfaceTexture t = st;
            int a = arrived.get();
            int pw = w, ph = h;
            if (t != null && a > latched && pw > 0 && ph > 0) {
                boolean got = true;
                for (; latched < a; latched++) {
                    try {
                        t.updateTexImage();
                    } catch (RuntimeException e) {
                        // (the picture stays as it was)
                        Host.log("view " + id + ": updateTexImage: " + e);
                        got = false;
                        latched = a;
                        break;
                    }
                }
                if (got) {
                    stamp = t.getTimestamp();
                    if (tex == 0 || texW != pw || texH != ph) {
                        tex = Streams.plain(tex, pw, ph);
                        texW = pw;
                        texH = ph;
                    }
                    Streams.blitFrame(t, ext, tex, pw, ph);
                    texture(id, tex);
                    float[] part = partAt(stamp);
                    part(id, part[0], part[1]);
                }
            }
            long say = sayAfter;
            if (say != Long.MAX_VALUE && tex != 0 && stamp >= say) {
                sayAfter = Long.MAX_VALUE;
                int n = sayPart;
                String said = "VIEWDRAWN " + id + (n > 0 ? " part " + n : "");
                // drawn as this frame, swapped as it ends, taken by the compositor at the next vsync, shown by the one
                // after (MBView's SHOT)
                Host.main.post(() -> Choreographer.getInstance().postFrameCallback(f ->
                        Choreographer.getInstance().postFrameCallback(g -> Host.log(said))));
            }
        }

        /** The view closed (GL thread): no frame draws it from now on. Its external texture, let go of with it. */
        int drop() {
            texture(id, 0);
            part(id, 0, 1);
            if (tex != 0) GLES30.glDeleteTextures(1, new int[] {tex}, 0);
            tex = 0;
            return ext;
        }

        /** Its producer stopped (main thread): its surface let go of, its SurfaceTexture and `ext` on the GL thread. */
        void letGo(int ext) {
            Surface s = surface;
            SurfaceTexture t = st;
            st = null;
            surface = null;
            if (s != null) s.release();
            if (t != null) doneWith.add(new Object[] {t, ext});
            Host.requestFrame();
        }

        /**
         * What it shows now, its texture's pixels, its top row first (GL thread); null when it has shown nothing.
         */
        Bitmap read() {
            if (tex == 0 || texW <= 0 || texH <= 0) return null;
            int[] fb = {0};
            GLES30.glGenFramebuffers(1, fb, 0);
            GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, fb[0]);
            GLES30.glFramebufferTexture2D(GLES30.GL_FRAMEBUFFER, GLES30.GL_COLOR_ATTACHMENT0, GLES30.GL_TEXTURE_2D, tex, 0);
            java.nio.ByteBuffer px = java.nio.ByteBuffer.allocateDirect(texW * texH * 4).order(java.nio.ByteOrder.nativeOrder());
            GLES30.glReadPixels(0, 0, texW, texH, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, px);
            GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0);
            GLES30.glDeleteFramebuffers(1, fb, 0);
            Bitmap b = Bitmap.createBitmap(texW, texH, Bitmap.Config.ARGB_8888);
            px.rewind();
            b.copyPixelsFromBuffer(px);
            return b;
        }
    }

    static void control(int id, int op, double value) {
        NView v = views.get(id);
        if (v != null) Host.main.post(() -> {
            if (!v.closed) v.control(op, value);
        });
    }

    static int info(int id, double[] out) {
        NView v = views.get(id);
        if (v == null) {
            if (!StreamLayer.has(id)) return -1;
            java.util.Arrays.fill(out, 0);
            return 1;
        }
        out[0] = v.duration;
        out[1] = v.position;
        out[2] = v.playing;
        if (v instanceof Video) {
            // buffering for the app only while it is to play and the player's reader waits on the app's bytes (Apple's
            // waiting to play): paused, a seek waiting on them (each move of a finger along the timeline) is no wait to
            // say; else it plays on, as asked
            Video vid = (Video) v;
            boolean waits = vid.bytesWaited.get() > 0;
            v.buffering = vid.exoBuffering && waits && vid.playWhenReady ? 1 : 0;
            if (vid.exoBuffering && !waits && vid.playWhenReady) out[2] = 1;
        }
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
     * a finger on it ("MODE SLOP", the slop in points), 3 a site's settings (JSON: head_wait_ms, backlog), 4 where the
     * app draws what takes a press over it ("X0 Y0 X1 Y1 …", points from the canvas's top left; "" none).
     */
    static void tell(int id, int what, String text) {
        NView v = views.get(id);
        if (v == null) {
            // (a stream's layer raised over the others: StreamLayer)
            if (what == 5) StreamLayer.raise(id);
            return;
        }
        if (what == 5) {
            // raised over the others (the app paints it after them): what takes a touch where they meet
            Host.main.post(() -> {
                if (v.clip != null && v.clip.getParent() != null) v.clip.bringToFront();
            });
        } else if (what == 1) {
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
        } else if (what == 4) {
            String[] p = text.isEmpty() ? new String[0] : text.split(" ");
            float d = Host.view.density;
            float[] covers = new float[p.length - p.length % 4];
            try {
                for (int j = 0; j < covers.length; j++) covers[j] = Float.parseFloat(p[j]) * d;
            } catch (NumberFormatException e) {
                covers = new float[0];
            }
            float[] c = covers;
            Host.main.post(() -> {
                if (v.clip != null) v.clip.covers = c;
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

    /** The next read a video asks of the app (its id, its offset and length in `out`), one it let go of (minus its id), or 0. */
    static int readNext(int id, double[] out) {
        NView v = views.get(id);
        if (!(v instanceof Video)) return 0;
        Video vid = (Video) v;
        Integer gone = vid.lettingGo.poll();
        if (gone != null) return -gone;
        Read r = vid.asked.poll();
        if (r == null) return 0;
        out[0] = r.offset;
        out[1] = r.length;
        return r.id;
    }

    /** Read `req`'s next bytes (after those it was given before), as the app has them; `more` while more of it comes. */
    static void readAnswer(int id, int req, byte[] data, double total, boolean more) {
        NView v = views.get(id);
        if (!(v instanceof Video)) return;
        Video vid = (Video) v;
        Read r = vid.waiting.get(req);
        if (r == null) return;
        int k;
        synchronized (r) {
            if (r.done) return;
            k = Math.min(data.length, r.length - r.got);
            System.arraycopy(data, 0, r.data, r.got, k);
            r.got += k;
            r.heard = System.nanoTime();
            if (total >= 0) vid.total = (long) total;
            if (total == -2) r.failed = true;
            if (!more || total == -2) {
                r.done = true;
                vid.waiting.remove(req);
            }
            r.notifyAll();
        }
        if (k > 0) {
            double before = vid.bytes;
            vid.bytes += k;
            vid.stood();
            // the first pieces, then one line every 4 MB
            if (vid.pieces++ < 4 || Math.floor(before / (4 << 20)) != Math.floor(vid.bytes / (4 << 20))) {
                Host.log("view " + id + ": read @" + r.offset + ": " + r.got + " of " + r.length + " bytes through the app"
                        + (more ? "" : ", its last") + " (total " + (long) vid.total + ", " + (long) vid.bytes + " so far)");
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
        /** Its reads asked of the app and not taken yet; those let go of (their ids) not told yet; those under way. */
        final ConcurrentLinkedQueue<Read> asked = new ConcurrentLinkedQueue<>();
        final ConcurrentLinkedQueue<Integer> lettingGo = new ConcurrentLinkedQueue<>();
        final ConcurrentHashMap<Integer, Read> waiting = new ConcurrentHashMap<>();
        final AtomicInteger nextRead = new AtomicInteger();
        volatile long total = -1;
        /** the pieces answered (GL thread): the first are logged */
        int pieces;
        /** since when it has waited once ready (elapsedRealtime; -1 it does not), and the bytes given by then (main thread) */
        long waitSince = -1;
        double waitBytes;
        ExoPlayer player;
        /**
         * (main thread) Where it is, how far on it has what it needs, how long it is: read of the player, the app told
         * where that changed (stood). As each frame of its picture is shown (its frames' listener), and on its own
         * clock (`tick`).
         */
        final Runnable sample = () -> {
            sampleAsked.set(false);
            if (closed || player == null) return;
            position = Math.max(0, player.getCurrentPosition());
            buffered = Math.max(0, player.getBufferedPosition());
            long dur = player.getDuration();
            if (dur != C.TIME_UNSET) duration = dur;
            stood();
        };
        final AtomicBoolean sampleAsked = new AtomicBoolean();
        /**
         * Its clock's tick: a sound playing has no frames shown to say where it is as it goes, so it is read 30 times a
         * second; a picture playing says so itself, each frame (and what it has on hand grows paused too: 4 a second).
         */
        final Runnable tick = new Runnable() {
            @Override
            public void run() {
                if (closed || player == null) return;
                sample.run();
                boolean sound = !player.getCurrentTracks().containsType(C.TRACK_TYPE_VIDEO);
                Host.main.postDelayed(this, playing > 0 && sound ? 33 : 250);
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
         * The file's bytes as the app gave them, kept on the disk while the view is open (a file of its own in the
         * app's cache, in blocks of BLOCK at their place in the file): what the player, its index's reader and a frame
         * grabbed read is asked of the app once, and read from here again (a seek back over what has played, a finger
         * along the timeline to and fro). A reader missing a block asks for a run of them from it (DriveSource.kt's
         * window: one after a jump, twice as many while it reads on from its last run, up to RUN, a core's part of 4
         * MB), stopping short of one here or on its way for another reader, whose run it reads from instead. A run's
         * bytes are read as they come, not once the whole run is here: on a slow link a player waits for the bytes it
         * needs, not for the 4 MB around them. A run is let go of (the app stops reading it) once no reader is on it
         * any more and some of it has not come: the player seeking elsewhere (or ahead of where the run has come to by
         * a block or more: what lies between is not waited for), a reader done; what came of it is kept.
         * One that brings nothing for STALL_NS fails (its reader's load tried again by the player).
         */
        static final int BLOCK = 256 << 10, RUN = 16;
        static final long STALL_NS = TimeUnit.SECONDS.toNanos(120);
        final Object keptLock = new Object();
        /** The blocks here whole (the file's last, to its end), and the runs on their way by the blocks they bring. */
        final java.util.BitSet have = new java.util.BitSet();
        final java.util.HashMap<Integer, Read> coming = new java.util.HashMap<>();
        java.io.File cacheDir, diskFile;
        java.nio.channels.FileChannel disk;
        /** No disk to keep it on (its file could not be made or written): each reader reads from its last run alone. */
        volatile boolean noDisk;
        static final java.util.concurrent.ExecutorService keepers = java.util.concurrent.Executors.newCachedThreadPool(r -> {
            Thread t = new Thread(r, "mbui-keep");
            t.setDaemon(true);
            return t;
        });
        /** Whether this process has cleared what views of an earlier one left on the disk (main thread). */
        static boolean swept;

        /**
         * How one reader of it goes: where its last run of blocks ended and how long it was; the run it reads from;
         * whether it is the player's (its waiting is the view's: bytesWaited).
         */
        static final class Pace {
            int end = -1, run = 1;
            Read read;
            boolean player;
        }

        /**
         * How many times the player's reader waits now for bytes still to come through the app; whether the player
         * says it buffers, and whether it is to play once it can (main thread's). It buffers for the app (info's 7)
         * only while it is to play and its reader waits so: a seek within what is here already (a finger along the
         * timeline over what has played), the player catching up to the very frame, is not waiting on the network,
         * and it plays on as it did (info's 2); paused, it waits for nothing to play.
         */
        final AtomicInteger bytesWaited = new AtomicInteger();
        volatile boolean exoBuffering, playWhenReady;

        /** Up to `len` bytes of the file at `p` into `buf` for the reader `pace`: how many (at least one), -1 at its end. */
        int bytesAt(long p, byte[] buf, int off, int len, Pace pace) throws IOException {
            if (len <= 0) return 0;
            for (;;) {
                if (closed) throw new InterruptedIOException("view " + id + " closed");
                if (total >= 0 && p >= total) return -1;
                // in the run it reads from, as it comes; but a jump ahead of where that run has come to by a block or
                // more (a seek) is not waited for through what lies between: that run let go of, one asked from there
                Read r = pace.read;
                if (r != null && p >= r.offset && p < r.offset + r.length && !r.done && p - (r.offset + r.got) >= BLOCK) {
                    synchronized (keptLock) {
                        leave(pace);
                    }
                    r = null;
                }
                if (r != null && p >= r.offset && p < r.offset + r.length) {
                    int k;
                    try {
                        k = r.take(this, pace, p, buf, off, len);
                    } catch (IOException e) {
                        // (one that failed: not read from again, its reader's load asking anew)
                        if (r.failed) {
                            synchronized (keptLock) {
                                leave(pace);
                            }
                        }
                        throw e;
                    }
                    if (k > 0) return k;
                    // it ended short of `p`: having brought nothing, at the file's end; else the rest asked again
                    if (r.got == 0) return -1;
                    synchronized (keptLock) {
                        leave(pace);
                    }
                }
                int b = (int) (p / BLOCK);
                boolean here;
                synchronized (keptLock) {
                    here = have.get(b);
                    if (!here) {
                        Read on = coming.get(b);
                        // (one ended, its keeper not done with it yet: not to be read from again)
                        if (on != null && on.done) {
                            coming.remove(b, on);
                            on = null;
                        }
                        if (on == null) {
                            int run = b == pace.end ? Math.min(pace.run * 2, RUN) : 1;
                            int n = 0;
                            while (n < run && !have.get(b + n) && !coming.containsKey(b + n)
                                    && (n == 0 || total < 0 || (long) (b + n) * BLOCK < total)) n++;
                            pace.end = b + n;
                            pace.run = run;
                            on = new Read(nextRead.incrementAndGet(), (long) b * BLOCK, n * BLOCK, b, n);
                            for (int i = 0; i < n; i++) coming.put(b + i, on);
                            ask(on);
                        }
                        if (pace.read != on) {
                            leave(pace);
                            pace.read = on;
                            on.users++;
                        }
                    }
                }
                if (!here) continue;
                int k = (int) Math.min(len, (long) (b + 1) * BLOCK - p);
                if (total >= 0) k = (int) Math.min(k, total - p);
                if (fromDisk(p, buf, off, k)) return k;
                // (not read back: asked again)
                synchronized (keptLock) {
                    have.clear(b);
                }
            }
        }

        /** The reader `pace` off the run it read from: that run let go of when no reader is on it and some of it is to come (keptLock held). */
        void leave(Pace pace) {
            Read r = pace.read;
            if (r == null) return;
            pace.read = null;
            if (--r.users > 0) return;
            boolean drop;
            synchronized (r) {
                drop = !r.done && r.got < r.length;
                if (drop) {
                    r.done = true;
                    r.gone = true;
                    r.notifyAll();
                }
            }
            if (drop) letGo(r);
        }

        /** A run no reader wants any more: the app told to stop it, its blocks not to come (keptLock held). */
        void letGo(Read r) {
            Host.log("view " + id + ": the read at " + r.offset + " let go of, " + r.got + " of its " + r.length + " bytes here");
            waiting.remove(r.id);
            for (int i = 0; i < r.blocks; i++) coming.remove(r.block + i, r);
            lettingGo.add(r.id);
            Host.requestFrame();
        }

        /** The run `r` asked of the app, its bytes kept on the disk as they come, block by block (keptLock held). */
        void ask(Read r) {
            waiting.put(r.id, r);
            askApp(() -> asked.add(r));
            keepers.execute(() -> keepAsItComes(r));
        }

        /**
         * What comes of run `r`, written to the disk a whole block at a time (and the file's last, to its end), until
         * it ends; nothing for STALL_NS fails it. On a keeper's thread.
         */
        void keepAsItComes(Read r) {
            int kept = 0;
            for (;;) {
                int got;
                boolean done;
                synchronized (r) {
                    try {
                        while (!r.done && r.got < (kept + 1) * BLOCK && !closed) {
                            long silent = System.nanoTime() - r.heard;
                            if (silent >= STALL_NS) {
                                Host.log("view " + id + ": nothing for the read at " + r.offset + " in "
                                        + TimeUnit.NANOSECONDS.toSeconds(silent) + " s");
                                r.failed = true;
                                r.done = true;
                                r.notifyAll();
                                break;
                            }
                            r.wait(Math.max(1, Math.min(1000, TimeUnit.NANOSECONDS.toMillis(STALL_NS - silent))));
                        }
                    } catch (InterruptedException e) {
                        return;
                    }
                    got = r.got;
                    done = r.done || closed;
                }
                boolean last = total >= 0 && r.offset + got >= total;
                int upto = done && last ? (got + BLOCK - 1) / BLOCK : got / BLOCK;
                if (upto > kept) {
                    keep(r, kept, upto, got);
                    kept = upto;
                }
                if (done) {
                    synchronized (keptLock) {
                        // failed or stalled: told to stop, as one let go of
                        if (r.failed && waiting.remove(r.id) != null && !closed) {
                            lettingGo.add(r.id);
                            Host.requestFrame();
                        }
                        for (int i = 0; i < r.blocks; i++) coming.remove(r.block + i, r);
                    }
                    return;
                }
            }
        }

        /** Blocks `from` to `to` of run `r` (its bytes to `got`), kept on the disk. */
        void keep(Read r, int from, int to, int got) {
            if (noDisk) return;
            try {
                synchronized (keptLock) {
                    if (closed) return;
                    if (disk == null) {
                        java.io.File dir = new java.io.File(cacheDir, "mbui-views");
                        if (!dir.isDirectory() && !dir.mkdirs()) throw new IOException("no " + dir);
                        diskFile = new java.io.File(dir, "view-" + android.os.Process.myPid() + "-" + id);
                        disk = new java.io.RandomAccessFile(diskFile, "rw").getChannel();
                    }
                }
                int a = from * BLOCK, z = Math.min(to * BLOCK, got);
                java.nio.ByteBuffer bb = java.nio.ByteBuffer.wrap(r.data, a, z - a);
                while (bb.hasRemaining()) disk.write(bb, r.offset + bb.position());
            } catch (IOException e) {
                if (!closed) Host.log("view " + id + ": its bytes not kept on the disk: " + e);
                noDisk = true;
                return;
            }
            synchronized (keptLock) {
                for (int i = from; i < to; i++) have.set(r.block + i);
            }
        }

        /** `k` bytes at `p` read back from the disk into `buf`; false if they could not be. */
        boolean fromDisk(long p, byte[] buf, int off, int k) {
            java.nio.channels.FileChannel d = disk;
            if (d == null) return false;
            try {
                java.nio.ByteBuffer bb = java.nio.ByteBuffer.wrap(buf, off, k);
                while (bb.hasRemaining()) {
                    if (d.read(bb, p + (bb.position() - off)) < 0) return false;
                }
                return true;
            } catch (IOException e) {
                return false;
            }
        }

        /** The reader `pace` done: off the run it read from (let go of if no other reader is on it). */
        void done(Pace pace) {
            synchronized (keptLock) {
                leave(pace);
            }
        }

        /** Until the file's whole size is known: the first run of reader `pace` read to its last answer, which says it. */
        void awaitTotal(Pace pace) throws IOException {
            Read r = pace.read;
            if (total >= 0 || r == null) return;
            synchronized (r) {
                try {
                    while (!r.done && total < 0) {
                        if (closed) throw new InterruptedIOException("view " + id + " closed");
                        r.wait(250);
                    }
                } catch (InterruptedException e) {
                    throw new InterruptedIOException();
                }
            }
            if (r.failed) throw new IOException("view " + id + ": the read at " + r.offset + " failed");
        }

        /** The file through the app's reads, for the system's retriever (as the player reads it). */
        final class Media extends MediaDataSource {
            final Pace pace = new Pace();

            @Override
            public int readAt(long position, byte[] buffer, int offset, int size) throws IOException {
                if (size == 0) return 0;
                int n = 0;
                while (n < size) {
                    int k = bytesAt(position + n, buffer, offset + n, size - n, pace);
                    if (k < 0) break;
                    n += k;
                }
                return n == 0 ? -1 : n;
            }

            @Override
            public long getSize() throws IOException {
                if (total < 0) {
                    bytesAt(0, new byte[1], 0, 1, pace);
                    awaitTotal(pace);
                }
                return total;
            }

            @Override
            public void close() {
                done(pace);
            }
        }

        /**
         * Its frames' times read from the file's index (an MP4's or a QuickTime file's sample table, in its moov, as
         * Media3's Mp4Extractor reads it for the player: the video track's samples' presentation times, sorted), off the
         * main thread. Only the index is read, never the samples (the file's whole video track, on a slow link a race
         * with the player for every byte); a file with none (another container, a fragmented MP4) has none to read.
         */
        void readFrames() {
            if (framesAsked) return;
            framesAsked = true;
            new Thread(() -> {
                StringBuilder out = new StringBuilder();
                ViewSource src = new ViewSource(this);
                try {
                    long[] times = indexTimes(src);
                    if (times != null) {
                        times = times.clone();
                        java.util.Arrays.sort(times);
                        for (int i = 0; i < times.length; i++) {
                            if (i > 0) out.append(',');
                            out.append(times[i] / 1000.0);
                        }
                    }
                    Host.log("view " + id + ": " + (times == null ? "no index to read its frames from" : times.length + " frames read"));
                } catch (Exception e) {
                    Host.log("view " + id + ": frames not read: " + e);
                } finally {
                    done(src.pace);
                }
                frames = out.toString();
                Host.requestFrame();
            }, "mbui-frames").start();
        }

        /**
         * The video track's samples' times (µs, in decode order) from the file's index, read through `src` as far as
         * its moov (Mp4Extractor, stopped once it has it: its seek map told); null when it has no such index.
         */
        long[] indexTimes(ViewSource src) throws IOException {
            Mp4Extractor x = new Mp4Extractor(SubtitleParser.Factory.UNSUPPORTED, 0);
            int[] video = {-1};
            boolean[] indexed = {false};
            x.init(new ExtractorOutput() {
                @Override
                public TrackOutput track(int track, int kind) {
                    if (kind == C.TRACK_TYPE_VIDEO && video[0] < 0) video[0] = track;
                    return new DiscardingTrackOutput();
                }

                @Override
                public void endTracks() {
                }

                @Override
                public void seekMap(SeekMap map) {
                    indexed[0] = true;
                }
            });
            Uri uri = Uri.parse("mbview://" + id + "/index");
            PositionHolder at = new PositionHolder();
            long from = 0;
            boolean sniffed = false;
            while (!indexed[0]) {
                long length = src.open(new DataSpec.Builder().setUri(uri).setPosition(from).build());
                try {
                    ExtractorInput in = new DefaultExtractorInput(src, from, length == C.LENGTH_UNSET ? C.LENGTH_UNSET : from + length);
                    if (!sniffed) {
                        if (!x.sniff(in)) return null;
                        in.resetPeekPosition();
                        sniffed = true;
                    }
                    int r = Extractor.RESULT_CONTINUE;
                    while (r == Extractor.RESULT_CONTINUE && !indexed[0]) r = x.read(in, at);
                    if (indexed[0]) break;
                    if (r != Extractor.RESULT_SEEK) return null;
                    from = at.position;
                } finally {
                    src.close();
                }
            }
            return video[0] < 0 ? new long[0] : x.getSampleTimestampsUs(video[0]);
        }

        /** The frame showing at `ms` grabbed whole at its own size (MediaMetadataRetriever, the closest), as a PNG. */
        void grab(double ms) {
            stillState = 1;
            still = new byte[0];
            new Thread(() -> {
                MediaMetadataRetriever r = new MediaMetadataRetriever();
                Media media = new Media();
                try {
                    r.setDataSource(media);
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
                    media.close();
                }
                Native.tell(Native.OUTSIDE_GRAB, id, stillState == 2 ? 1 : -1);
            }, "mbui-grab").start();
        }

        /**
         * The frame showing now, its picture's (its content at the video's proportions, not the transform the app's
         * zoom puts on it), at most `side` pixels on its longer side, as a JPEG: `still` once it is made (main thread;
         * read on the GL thread).
         * As still.fail's Android app keeps the frame a video was left at (VideoViewer.kt frameOut: getBitmap).
         */
        void grabShown(double side) {
            stillState = 1;
            still = new byte[0];
            Picture p = picture;
            if (p == null || framed <= 0 || nw <= 0 || nh <= 0) {
                grabbedShown(null, 0, 0);
                return;
            }
            double k = Math.min(1.0, side / Math.max(nw, nh));
            int gw = Math.max(1, (int) Math.round(nw * k)), gh = Math.max(1, (int) Math.round(nh * k));
            Host.view.toGL(() -> {
                Bitmap b = null;
                try {
                    b = p.read();
                } catch (RuntimeException e) {
                    Host.log("view " + id + ": the frame shown not grabbed: " + e);
                }
                grabbedShown(b, gw, gh);
            });
        }

        /** The frame shown, read (null: none), made a JPEG of `gw` × `gh` on a thread of its own. */
        private void grabbedShown(Bitmap b, int gw, int gh) {
            if (b == null) {
                stillState = -1;
                Native.tell(Native.OUTSIDE_GRAB, id, -1);
                return;
            }
            new Thread(() -> {
                Bitmap shot = Bitmap.createScaledBitmap(b, gw, gh, true);
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                shot.compress(Bitmap.CompressFormat.JPEG, 90, out);
                if (shot != b) shot.recycle();
                b.recycle();
                still = out.toByteArray();
                stillState = 2;
                Host.log("view " + id + ": the frame shown grabbed (" + still.length + " bytes)");
                Native.tell(Native.OUTSIDE_GRAB, id, 1);
            }, "mbui-grab").start();
        }

        @Override
        void make(Context c) {
            cacheDir = c.getCacheDir();
            // what an earlier process's views left on the disk (it ended without closing them), cleared once
            if (!swept) {
                swept = true;
                java.io.File[] left = new java.io.File(cacheDir, "mbui-views").listFiles();
                if (left != null) for (java.io.File f : left) f.delete();
            }
            // the frames between a key frame and the one a seek goes to decoded without being put out (Android 14 on:
            // MediaCodec's decode-only flag), so an exact seek gets there sooner
            player = new ExoPlayer.Builder(c, new DefaultRenderersFactory(c).experimentalSetEnableMediaCodecBufferDecodeOnlyFlag(true)).build();
            player.setSeekParameters(SeekParameters.EXACT);
            // its frames onto its picture, which the canvas draws where the app puts the video
            player.setVideoSurface(picture.surface);
            // each frame as it is shown: where it is then, the app told (on the main thread, the player's own)
            player.setVideoFrameMetadataListener((presentationUs, releaseNs, format, mediaFormat) -> {
                if (sampleAsked.compareAndSet(false, true)) Host.main.post(sample);
            });
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
                    exoBuffering = s == Player.STATE_BUFFERING;
                    // a wait once ready (a seek, its bytes not here yet), said with how long it took and what came
                    // through the app meanwhile (none: it waited on its own decoding, not on the network)
                    if (s == Player.STATE_BUFFERING && state == 1 && waitSince < 0) {
                        waitSince = android.os.SystemClock.elapsedRealtime();
                        waitBytes = bytes;
                        Host.log("view " + id + ": waiting at " + player.getCurrentPosition() + " ms");
                    } else if (s != Player.STATE_BUFFERING && waitSince >= 0) {
                        Host.log("view " + id + ": waited " + (android.os.SystemClock.elapsedRealtime() - waitSince) + " ms, "
                                + (long) (bytes - waitBytes) + " bytes through the app meanwhile");
                        waitSince = -1;
                    }
                    ended = s == Player.STATE_ENDED ? 1 : 0;
                    if (s == Player.STATE_ENDED) playing = 0;
                    stood();
                }

                @Override
                public void onPlayWhenReadyChanged(boolean will, int reason) {
                    playWhenReady = will;
                    stood();
                }

                @Override
                public void onIsPlayingChanged(boolean is) {
                    playing = is ? 1 : 0;
                    if (is) {
                        Host.main.removeCallbacks(tick);
                        Host.main.post(tick);
                    }
                    stood();
                }

                @Override
                public void onVideoSizeChanged(VideoSize s) {
                    if (s.width > 0 && s.height > 0) {
                        nw = s.width * s.pixelWidthHeightRatio;
                        nh = s.height;
                        // (its picture as large as its frames, drawn at the video's proportions where the app puts it)
                        picture.w = s.width;
                        picture.h = s.height;
                        stood();
                    }
                }

                @Override
                public void onRenderedFirstFrame() {
                    if (framed == 0) Host.log("view " + id + ": first frame shown");
                    framed = 1;
                    tell(1);  // ready for the app: its first frame shows
                    stood();
                }

                @Override
                public void onPlayerError(PlaybackException e) {
                    state = -1;
                    playing = 0;
                    Host.log("view " + id + ": cannot play: " + e.getErrorCodeName() + " " + e.getMessage());
                    tell(-1);
                    stood();
                }
            });
            ProgressiveMediaSource source = new ProgressiveMediaSource.Factory(() -> new ViewSource(this, true))
                    .createMediaSource(MediaItem.fromUri("mbview://" + id + "/file"));
            player.setMediaSource(source);
            player.prepare();
            Host.main.post(tick);
        }

        @Override
        void pictureAnew() {
            if (player != null) player.setVideoSurface(picture.surface);
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
                    // whole ms, floored: Media3 shows the first frame from there, so a frame's start (1583.33) is
                    // that frame (to 1584, the next)
                    player.setSeekParameters(SeekParameters.EXACT);
                    player.seekTo((long) Math.floor(value));
                    position = value;
                    stood();
                    break;
                // about there, at once: the key frame nearest it (nothing before the frame asked decoded first)
                case 11:
                    player.setSeekParameters(SeekParameters.CLOSEST_SYNC);
                    player.seekTo((long) Math.floor(value));
                    position = value;
                    stood();
                    break;
                case 4: player.setPlaybackParameters(new PlaybackParameters((float) value)); break;
                // a finger along its timeline: its seeks one after another, each shown (Media3's scrubbing mode)
                case 9: player.setScrubbingModeEnabled(value > 0); break;
                // how loud, 0 to 1 (NativeView::volume)
                case 10: player.setVolume((float) Math.max(0, Math.min(1, value))); break;
                case 20: readFrames(); break;
                case 21: grab(value); break;
                case 22: grabShown(value); break;
                default: break;
            }
        }

        @Override
        void destroy() {
            Host.main.removeCallbacks(tick);
            // its readers and keepers woken: the view is closed (the app stops its reads as it closes it)
            for (Read r : waiting.values()) {
                synchronized (r) {
                    r.notifyAll();
                }
            }
            if (player != null) player.release();
            player = null;
            // what was kept of its file, gone with it
            synchronized (keptLock) {
                try {
                    if (disk != null) disk.close();
                } catch (IOException ignored) {
                }
                disk = null;
                if (diskFile != null) diskFile.delete();
            }
        }
    }

    /**
     * What the player reads the file through: the view's bytes as they are kept (Video.bytesAt: on the disk once the
     * app has given them, asked of it in runs that grow while reads go on from each other, small again after a jump).
     */
    static final class ViewSource extends BaseDataSource {
        final Video v;
        final Video.Pace pace = new Video.Pace();
        final byte[] probe = new byte[1];
        Uri uri;
        long position, remaining;
        boolean opened;

        ViewSource(Video v) {
            this(v, false);
        }

        /** The view's file read through the app; `player`: the player's own reader (Pace.player). */
        ViewSource(Video v, boolean player) {
            super(true);
            this.v = v;
            pace.player = player;
        }

        @Override
        public long open(DataSpec spec) throws IOException {
            uri = spec.uri;
            long start = spec.position;
            position = start;
            transferInitializing(spec);
            // its size, from the first read (none there: it ends where it is opened; its size said with its last answer)
            if (v.total < 0 && v.bytesAt(start, probe, 0, 1, pace) < 0 && v.total < 0) v.total = start;
            v.awaitTotal(pace);
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
            int n = v.bytesAt(position, buffer, offset, (int) Math.min(length, remaining), pace);
            if (n < 0) return C.RESULT_END_OF_INPUT;
            position += n;
            remaining -= n;
            bytesTransferred(n);
            return n;
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

    /**
     * A page, its WebView as large as its frame. One taller than its picture can be (partMost; a page placed in a
     * message is as tall as its content: a catalogue of icons twenty screens and 50,000 pixels tall, past the 16,384
     * a phone's GPU takes, had no picture at all) is drawn a part of it at a time: its frame and its WebView that part,
     * the page scrolled to it (scrollToPart), moved on as what is seen of the page nears the part's edge (partOf). Each
     * picture says which part of the page it is (drawnPart), and the canvas draws it there and nothing of the page
     * outside it.
     */
    static final class Page extends NView {
        final String html;
        /** (main thread) The top of the part of it its frame is, its page scrolled to (pixels); -1: all of it. */
        int partTop = -1;

        Page(int id, String html) {
            super(id, 2);
            this.html = html;
        }

        /**
         * The tallest part of a page drawn at once (pixels): three of the screen's heights (what is seen, and a screen's
         * worth either side of it to scroll into before the next part is drawn), at most the GPU's largest texture.
         */
        static int partMost() {
            int most = textureMost > 0 ? textureMost : 2048;
            MBView m = Host.view;
            int screen = m != null ? m.getHeight() : 0;
            return screen > 0 ? Math.min(3 * screen, most) : most;
        }

        @Override
        void partOf(float[] to, float[] was, boolean shown) {
            float full = to[3], most = partMost();
            if (full <= most) {
                super.partOf(to, was, shown);
                return;
            }
            float top = was != null && Math.abs(was[10] - most) < 0.5f ? Math.min(was[9], full - most) : -1;
            // what is seen of it, from its top
            float s0 = Math.max(0, to[5] - to[1]), s1 = Math.min(full, to[7] - to[1]);
            if (shown && s1 > s0) {
                // kept while what is seen is no nearer its edge than a quarter of the room left around it (where there
                // is more of the page that way); else the part about what is seen, as much of it above as below
                float near = (most - (s1 - s0)) / 4;
                boolean keeps = top >= 0 && (top <= 0 || s0 - top >= near) && (top + most >= full || top + most - s1 >= near);
                if (!keeps) top = Math.max(0, Math.min(full - most, Math.round((s0 + s1 - most) / 2)));
            } else if (top < 0) {
                top = 0;
            }
            to[9] = Math.round(top);
            to[10] = most;
        }

        @Override
        float[] drawnPart(int h) {
            float full = at[3];
            if (partTop < 0 || web == null || full <= 0) return WHOLE;
            // (the part the page is scrolled to now, which the WebView's scroll mirrors, whatever the part asked: not
            // there yet (the page not loaded, or not that tall yet), or scrolled elsewhere (by a finger, by the page),
            // it is asked again)
            int top = web.getScrollY();
            if (!atPart(top)) web.post(this::scrollToPart);
            if (drawLog()) Host.log("VIEWPIC " + id + " scrolled " + top + " part " + partTop + " tall " + h + " of " + full + " page "
                    + Math.round(web.getContentHeight() * Host.view.density));
            return new float[] {top / full, h / full};
        }

        @Override
        boolean partDrawn() {
            return partTop < 0 || web == null || atPart(web.getScrollY());
        }

        /** Whether the page is scrolled to the part its frame is, but for the rounding of its CSS pixels (main thread). */
        private boolean atPart(int top) {
            return Math.abs(top - partTop) <= 1;
        }

        @Override
        void moved() {
            if (web == null) return;
            boolean part = at[10] < at[3] - 0.5f;
            boolean was = partTop >= 0;
            int top = part ? Math.round(at[9]) : -1;
            boolean moves = top != partTop;
            partTop = top;
            if (part != was) {
                web.setVerticalScrollBarEnabled(!part);
                if (!part) script(SCROLL_TOP.replace("$", "0"));
            }
            scrollToPart();
            if (moves && part) drawnAgain();
        }

        /**
         * The page scrolled to the part its frame is, by its own script (main thread). A page's own scroll: the WebView's
         * (WebView.scrollTo) is a user's, which a page whose root does not scroll takes nothing of (as a viz's does not:
         * ember-viz.css, overflow: hidden), and a picture of its top said to be a part of it far down (0.1.5309).
         */
        void scrollToPart() {
            if (web == null || partTop < 0 || atPart(web.getScrollY())) return;
            script(SCROLL_TOP.replace("$", Float.toString(partTop / Host.view.density)));
        }

        /** The page's script to scroll its root to `$` (CSS pixels) at once, whatever its scroll-behavior. */
        static final String SCROLL_TOP = "try{scrollTo({top:$,behavior:'instant'})}catch(e){scrollTo(0,$)}";

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
            // all of its page drawn, not only what was on the screen as it last drew: its picture is moved by the
            // canvas, the page not told (a page scrolled in from off the screen shows whole)
            s.setOffscreenPreRaster(true);
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
                    stood();
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
            // (its frame is its rect: put moves and sizes it, nothing here)
            clip.addView(web, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
            web.loadDataWithBaseURL(null, html, "text/html", "utf-8", null);
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
            // (all of its page drawn, as a page's: its picture is moved by the canvas)
            st.setOffscreenPreRaster(true);
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
                    stood();
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
            // laid out at its rect over its scale, drawn at its scale from its top left (its frame's: the frame is its
            // rect, put moves it)
            int w = Math.round(at[2] / scale), h = Math.round(at[3] / scale);
            if (p.leftMargin != 0 || p.topMargin != 0 || p.width != w || p.height != h) {
                p.leftMargin = 0;
                p.topMargin = 0;
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
