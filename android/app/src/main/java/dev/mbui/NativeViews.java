package dev.mbui;

import android.annotation.SuppressLint;
import android.content.ContentValues;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Matrix;
import android.net.Uri;
import android.provider.MediaStore;
import android.view.TextureView;
import android.view.View;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
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

import java.io.IOException;
import java.io.InterruptedIOException;
import java.io.OutputStream;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
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
        FrameLayout clip;
        View content;
        volatile boolean closed;
        // how it stands, for info (the GL thread reads these)
        volatile int state;
        volatile double duration = -1, position, playing, nw, nh, bytes, framed, buffering;
        // placed: x y w h cx0 cy0 cx1 cy1, in pixels; shown
        final float[] at = new float[8];
        boolean shown;

        NView(int id, int kind) {
            this.id = id;
            this.kind = kind;
        }

        void make(Context c) {}

        void moved() {}

        void control(int op, double value) {}

        void destroy() {}
    }

    // ---- the GL thread ----

    static int open(int kind, String arg) {
        if (kind != 1 && kind != 2) return 0;
        int id = next.incrementAndGet();
        NView v = kind == 1 ? new Video(id, arg) : new Page(id, arg);
        views.put(id, v);
        Host.log("view " + id + ": open " + (kind == 1 ? "video " + arg : "page of " + arg.length() + " characters"));
        Host.main.post(() -> {
            if (v.closed || layer == null) return;
            v.clip = new FrameLayout(layer.getContext());
            v.clip.setClipChildren(true);
            v.clip.setBackgroundColor(kind == 1 ? Color.BLACK : Color.WHITE);
            v.clip.setVisibility(View.GONE);
            v.make(layer.getContext());
            layer.addView(v.clip, new FrameLayout.LayoutParams(0, 0));
        });
        return id;
    }

    static void place(int id, float x, float y, float w, float h, float cx0, float cy0, float cx1, float cy1,
                      boolean shown) {
        NView v = views.get(id);
        if (v == null) return;
        float d = Host.view.density;
        float[] to = {x * d, y * d, w * d, h * d, cx0 * d, cy0 * d, cx1 * d, cy1 * d};
        Host.main.post(() -> {
            if (v.closed || v.clip == null) return;
            boolean same = v.shown == shown;
            for (int i = 0; i < 8 && same; i++) same = Math.abs(v.at[i] - to[i]) < 0.5f;
            if (same) return;
            System.arraycopy(to, 0, v.at, 0, 8);
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
        });
    }

    static void close(int id) {
        NView v = views.remove(id);
        if (v == null) return;
        v.closed = true;
        Host.log("view " + id + ": closed (" + (long) v.bytes + " bytes given)");
        Host.main.post(() -> {
            v.destroy();
            if (v.clip != null && layer != null) layer.removeView(v.clip);
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
        return v.state;
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
                long dur = player.getDuration();
                if (dur != C.TIME_UNSET) duration = dur;
                Host.main.postDelayed(this, playing > 0 ? 33 : 250);
            }
        };

        Video(int id, String type) {
            super(id, 1);
            this.type = type;
        }

        /** Bytes from `offset` (at most `length`), asked of the app and waited for: on the player's loading thread. */
        Read ask(long offset, int length) throws IOException {
            Read r = new Read(nextRead.incrementAndGet(), offset, length);
            waiting.put(r.id, r);
            asked.add(r);
            Host.requestFrame();
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
                    buffering = s == Player.STATE_BUFFERING ? 1 : 0;
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
                    Host.requestFrame();
                }

                @Override
                public void onPlayerError(PlaybackException e) {
                    state = -1;
                    playing = 0;
                    Host.log("view " + id + ": cannot play: " + e.getErrorCodeName() + " " + e.getMessage());
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
        WebView web;

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
            web.setWebViewClient(new WebViewClient() {
                @Override
                public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                    return true;
                }

                @Override
                public void onPageFinished(WebView view, String url) {
                    if (state == 0) {
                        state = 1;
                        framed = 1;
                        Host.log("view " + id + ": page loaded (" + bytes + " bytes of HTML)");
                    }
                    Host.requestFrame();
                }

                @Override
                public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                    if (request.isForMainFrame()) {
                        state = -1;
                        Host.log("view " + id + ": the page failed: " + error.getDescription());
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
        void destroy() {
            if (web != null) {
                clip.removeView(web);
                web.destroy();
            }
            web = null;
        }
    }
}
