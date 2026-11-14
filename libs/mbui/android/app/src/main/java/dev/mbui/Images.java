package dev.mbui;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.ColorSpace;
import android.graphics.ImageDecoder;
import android.graphics.Matrix;
import android.media.ExifInterface;
import android.opengl.GLES30;
import android.opengl.GLUtils;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.ByteBuffer;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Images: read and decoded on background threads straight to the size asked
 * for, EXIF orientation applied, then uploaded on the GL thread as
 * premultiplied RGBA textures the C renderer draws. Local/in-memory decodes,
 * gallery thumbnails (content://) and remote fetches run on separate pools so a
 * burst of gallery thumbnails or slow URLs never starves an image just picked.
 */
final class Images {
    // local files and bytes already in memory (picked previews, icons, marks)
    static final ExecutorService pool = Executors.newFixedThreadPool(3);
    // content:// URIs (gallery thumbnails and video stills: MediaProvider IPC)
    static final ExecutorService thumbs = Executors.newFixedThreadPool(2);
    // http(s):// fetches, kept off local decodes when the network stalls
    static final ExecutorService remote = Executors.newFixedThreadPool(2);

    static final class Req {
        final String src;
        final byte[] data;
        final int maxPx;
        /** How to make it again if not by decoding (a PDF's page, Pdfs.java). */
        final Runnable redo;

        Req(String src, byte[] data, int maxPx) {
            this(src, data, maxPx, null);
        }

        Req(String src, byte[] data, int maxPx, Runnable redo) {
            this.src = src;
            this.data = data;
            this.maxPx = maxPx;
            this.redo = redo;
        }
    }

    // what each live image was loaded from, to decode it again if the GL
    // context (and with it every texture) is lost; written on the GL thread,
    // checked by workers so freed requests skip work
    static final ConcurrentHashMap<Integer, Req> live = new ConcurrentHashMap<>();

    static ExecutorService poolFor(Req r) {
        if (r.data != null) return pool;
        if (r.src.startsWith("content://")) return thumbs;
        if (r.src.startsWith("http://") || r.src.startsWith("https://")) return remote;
        return pool;
    }

    static void submit(int id, Req r) {
        poolFor(r).execute(() -> decode(id, r));
    }

    static void load(int id, String src, byte[] data, int maxPx) {
        Req r = new Req(src, data, maxPx);
        live.put(id, r);
        submit(id, r);
    }

    // mbui-render (android_host.c mb_render_init_offscreen): its main holds the GL thread while it waits for its
    // images, so their uploads are kept here and done when it asks (pump), on that thread
    static volatile boolean held;
    static final ConcurrentLinkedQueue<Runnable> heldUploads = new ConcurrentLinkedQueue<>();

    static void hold() {
        held = true;
    }

    static void pump() {
        for (Runnable r; (r = heldUploads.poll()) != null; ) r.run();
    }

    static void toGL(Runnable r) {
        if (held) {
            heldUploads.add(r);
            return;
        }
        MBView v = Host.view;
        if (v != null) v.toGL(r);
    }

    static void free(int id) {
        live.remove(id);
    }

    static void reload() {
        for (Map.Entry<Integer, Req> e : live.entrySet()) {
            int id = e.getKey();
            Req r = e.getValue();
            if (r.redo != null) r.redo.run();
            else submit(id, r);
        }
    }

    static Bitmap decodeSource(ImageDecoder.Source src, int maxPx, int[] orig) throws IOException {
        Bitmap b = ImageDecoder.decodeBitmap(src, (d, info, s) -> {
            int w = info.getSize().getWidth(), h = info.getSize().getHeight();
            orig[0] = w;
            orig[1] = h;
            double k = Math.min(1.0, maxPx / (double) Math.max(w, h));
            if (k < 1) {
                d.setTargetSize(Math.max(1, (int) Math.round(w * k)),
                        Math.max(1, (int) Math.round(h * k)));
            }
            d.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE);
            d.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB));
        });
        if (b.getConfig() != Bitmap.Config.ARGB_8888) {
            Bitmap c = b.copy(Bitmap.Config.ARGB_8888, false);
            b.recycle();
            b = c;
        }
        return b;
    }

    static void decode(int id, Req r) {
        if (live.get(id) != r) return;
        long t0 = System.nanoTime();
        int[] orig = new int[2];
        Bitmap b = null;
        try {
            byte[] data = r.data;
            if (data == null && r.src.startsWith("content://")) {
                android.content.ContentResolver cr = Host.activity.getContentResolver();
                android.net.Uri uri = android.net.Uri.parse(r.src);
                // a photo or video of the gallery (Gallery.java), or a file held by its address (Picks.java):
                // its thumbnail first (a video's still, a photo's cached preview), else the image itself
                try {
                    Bitmap t = cr.loadThumbnail(uri, new android.util.Size(r.maxPx, r.maxPx), null);
                    orig[0] = t.getWidth();
                    orig[1] = t.getHeight();
                    b = t.getConfig() == Bitmap.Config.ARGB_8888 ? t : t.copy(Bitmap.Config.ARGB_8888, false);
                    if (b != t) t.recycle();
                } catch (Exception thumbErr) {
                    b = decodeSource(ImageDecoder.createSource(cr, uri), r.maxPx, orig);
                }
            } else {
                if (data == null && (r.src.startsWith("http://") || r.src.startsWith("https://"))) {
                    data = fetch(r.src);
                    if (live.get(id) != r) return;
                }
                String path = r.src.startsWith("file://") ? r.src.substring(7) : r.src;
                try {
                    // minSdk is 30, so ImageDecoder is always there; BitmapFactory
                    // is the second try for what it can't read
                    b = decodeSource(data != null
                            ? ImageDecoder.createSource(ByteBuffer.wrap(data))
                            : ImageDecoder.createSource(new File(path)), r.maxPx, orig);
                } catch (IOException e) {
                    b = withFactory(data, path, r.maxPx, orig);
                    if (b == null) throw e;
                    if (b.getConfig() != Bitmap.Config.ARGB_8888) {
                        Bitmap c = b.copy(Bitmap.Config.ARGB_8888, false);
                        b.recycle();
                        b = c;
                    }
                }
            }
        } catch (Throwable e) {
            Host.log("image " + r.src + ": " + e);
            b = null;
        }
        if (Host.bench != 0 && b != null) {
            Host.log("image " + orig[0] + "x" + orig[1] + " -> " + b.getWidth() + "x" + b.getHeight()
                    + " in " + (System.nanoTime() - t0) / 1000000 + " ms: " + r.src);
        }
        Bitmap bmp = b;
        toGL(() -> upload(id, bmp, orig[0], orig[1]));
    }

    /** Older decoders: a power-of-two subsample, then scaled and turned. */
    static Bitmap withFactory(byte[] data, String path, int maxPx, int[] orig) throws IOException {
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inJustDecodeBounds = true;
        if (data != null) BitmapFactory.decodeByteArray(data, 0, data.length, o);
        else BitmapFactory.decodeFile(path, o);
        int w = o.outWidth, h = o.outHeight;
        if (w <= 0 || h <= 0) return null;
        o.inJustDecodeBounds = false;
        o.inSampleSize = 1;
        while (Math.max(w, h) / (o.inSampleSize * 2) >= maxPx) o.inSampleSize *= 2;
        Bitmap b = data != null ? BitmapFactory.decodeByteArray(data, 0, data.length, o)
                : BitmapFactory.decodeFile(path, o);
        if (b == null) return null;
        ExifInterface ex = data != null ? new ExifInterface(new ByteArrayInputStream(data))
                : new ExifInterface(path);
        int turn = ex.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
        float k = (float) Math.min(1.0, maxPx / (double) Math.max(b.getWidth(), b.getHeight()));
        Matrix m = new Matrix();
        m.setScale(k, k);
        switch (turn) {
            case ExifInterface.ORIENTATION_FLIP_HORIZONTAL: m.postScale(-1, 1); break;
            case ExifInterface.ORIENTATION_ROTATE_180: m.postRotate(180); break;
            case ExifInterface.ORIENTATION_FLIP_VERTICAL: m.postScale(1, -1); break;
            case ExifInterface.ORIENTATION_TRANSPOSE: m.postRotate(90); m.postScale(-1, 1); break;
            case ExifInterface.ORIENTATION_ROTATE_90: m.postRotate(90); break;
            case ExifInterface.ORIENTATION_TRANSVERSE: m.postRotate(-90); m.postScale(-1, 1); break;
            case ExifInterface.ORIENTATION_ROTATE_270: m.postRotate(-90); break;
        }
        boolean swap = turn >= ExifInterface.ORIENTATION_TRANSPOSE;
        orig[0] = swap ? h : w;
        orig[1] = swap ? w : h;
        if (m.isIdentity()) return b;
        Bitmap t = Bitmap.createBitmap(b, 0, 0, b.getWidth(), b.getHeight(), m, true);
        if (t != b) b.recycle();
        return t;
    }

    static byte[] fetch(String url) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(15_000);
        c.setReadTimeout(30_000);
        try (InputStream in = c.getInputStream()) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[64 * 1024];
            for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
            return out.toByteArray();
        } finally {
            c.disconnect();
        }
    }

    // ---- GL thread ----

    static void upload(int id, Bitmap b, int ow, int oh) {
        if (!live.containsKey(id)) {  // freed meanwhile
            if (b != null) b.recycle();
            return;
        }
        int[] t = {0};
        if (b != null) {
            GLES30.glGenTextures(1, t, 0);
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, t[0]);
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR);
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR);
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE);
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE);
            // Bitmaps are premultiplied, and uploaded as they are
            GLUtils.texImage2D(GLES30.GL_TEXTURE_2D, 0, b, 0);
        }
        Native.imageDone(id, t[0], b != null ? b.getWidth() : 0, b != null ? b.getHeight() : 0, ow, oh);
        if (b != null) b.recycle();
    }
}
